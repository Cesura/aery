﻿/// Structures for data received: rows and result sets (ie, a range of rows).
module mysql.result;

import std.conv;
import std.exception;
import std.range;
import std.string;
import std.variant;

import mysql.connection;
import mysql.exceptions;
import mysql.protocol.comms;
import mysql.protocol.extra_types;
import mysql.protocol.packets;

/++
A struct to represent a single row of a result set.

Type_Mappings: $(TYPE_MAPPINGS)
+/
/+
The row struct is used for both 'traditional' and 'prepared' result sets.
It consists of parallel arrays of Variant and bool, with the bool array
indicating which of the result set columns are NULL.

I have been agitating for some kind of null indicator that can be set for a
Variant without destroying its inherent type information. If this were the
case, then the bool array could disappear.
+/
struct Row
{
	import mysql.connection;

package:
	Variant[]   _values; // Temporarily "package" instead of "private"
private:
	bool[]      _nulls;

public:

	/++
	A constructor to extract the column data from a row data packet.
	
	If the data for the row exceeds the server's maximum packet size, then several packets will be
	sent for the row that taken together constitute a logical row data packet. The logic of the data
	recovery for a Row attempts to minimize the quantity of data that is bufferred. Users can assist
	in this by specifying chunked data transfer in cases where results sets can include long
	column values.
	
	Type_Mappings: $(TYPE_MAPPINGS)
	+/
	this(Connection con, ref ubyte[] packet, ResultSetHeaders rh, bool binary)
	{
		ctorRow(con, packet, rh, binary, _values, _nulls);
	}

	/++
	Simplify retrieval of a column value by index.
	
	To check for null, use Variant's `type` property:
	`row[index].type == typeid(typeof(null))`

	Type_Mappings: $(TYPE_MAPPINGS)

	Params: i = the zero based index of the column whose value is required.
	Returns: A Variant holding the column value.
	+/
	inout(Variant) opIndex(size_t i) inout
	{
		enforce!MYX(_nulls.length > 0, format("Cannot get column index %d. There are no columns", i));
		enforce!MYX(i < _nulls.length, format("Cannot get column index %d. The last available index is %d", i, _nulls.length-1));
		return _values[i];
	}

	/++
	Check if a column in the result row was NULL
	
	Params: i = The zero based column index.
	+/
	bool isNull(size_t i) const pure nothrow { return _nulls[i]; }

	/++
	Get the number of elements (columns) in this row.
	+/
	@property size_t length() const pure nothrow { return _values.length; }

	///ditto
	alias opDollar = length;

	/++
	Move the content of the row into a compatible struct
	
	This method takes no account of NULL column values. If a column was NULL,
	the corresponding Variant value would be unchanged in those cases.
	
	The method will throw if the type of the Variant is not implicitly
	convertible to the corresponding struct member.
	
	Type_Mappings: $(TYPE_MAPPINGS)

	Params:
	S = A struct type.
	s = A ref instance of the type
	+/
	void toStruct(S)(ref S s) if (is(S == struct))
	{
		foreach (i, dummy; s.tupleof)
		{
			static if(__traits(hasMember, s.tupleof[i], "nullify") &&
					  is(typeof(s.tupleof[i].nullify())) && is(typeof(s.tupleof[i].get)))
			{
				if(!_nulls[i])
				{
					enforce!MYX(_values[i].convertsTo!(typeof(s.tupleof[i].get))(),
						"At col "~to!string(i)~" the value is not implicitly convertible to the structure type");
					s.tupleof[i] = _values[i].get!(typeof(s.tupleof[i].get));
				}
				else
					s.tupleof[i].nullify();
			}
			else
			{
				if(!_nulls[i])
				{
					enforce!MYX(_values[i].convertsTo!(typeof(s.tupleof[i]))(),
						"At col "~to!string(i)~" the value is not implicitly convertible to the structure type");
					s.tupleof[i] = _values[i].get!(typeof(s.tupleof[i]));
				}
				else
					s.tupleof[i] = typeof(s.tupleof[i]).init;
			}
		}
	}

	void show()
	{
		import std.stdio;

		foreach(Variant v; _values)
			writef("%s, ", v.toString());
		writeln("");
	}
}

/++
An $(LINK2 http://dlang.org/phobos/std_range_primitives.html#isInputRange, input range)
of Row.

This is returned by the `mysql.commands.query` functions.

The rows are downloaded one-at-a-time, as you iterate the range. This allows
for low memory usage, and quick access to the results as they are downloaded.
This is especially ideal in case your query results in a large number of rows.

However, because of that, this `ResultRange` cannot offer random access or
a `length` member. If you need random access, then just like any other range,
you can simply convert this range to an array via
$(LINK2 https://dlang.org/phobos/std_array.html#array, `std.array.array()`).

A `ResultRange` becomes invalidated (and thus cannot be used) when the server
is sent another command on the same connection. When an invalidated `ResultRange`
is used, a `mysql.exceptions.MYXInvalidatedRange` is thrown. If you need to
send the server another command, but still access these results afterwords,
you can save the results for later by converting this range to an array via
$(LINK2 https://dlang.org/phobos/std_array.html#array, `std.array.array()`).

Type_Mappings: $(TYPE_MAPPINGS)

Example:
---
ResultRange oneAtATime = myConnection.query("SELECT * from myTable");
Row[]       allAtOnce  = myConnection.query("SELECT * from myTable").array;
---
+/
struct ResultRange
{
private:
	Connection       _con;
	ResultSetHeaders _rsh;
	Row              _row; // current row
	string[]         _colNames;
	size_t[string]   _colNameIndicies;
	ulong            _numRowsFetched;
	ulong            _commandID; // So we can keep track of when this is invalidated

	void ensureValid() const pure
	{
		enforce!MYXInvalidatedRange(isValid,
			"This ResultRange has been invalidated and can no longer be used.");
	}

package:
	this (Connection con, ResultSetHeaders rsh, string[] colNames)
	{
		_con       = con;
		_rsh       = rsh;
		_colNames  = colNames;
		_commandID = con.lastCommandID;
		popFront();
	}

public:
	/++
	Check whether the range can still be used, or has been invalidated.

	A `ResultRange` becomes invalidated (and thus cannot be used) when the server
	is sent another command on the same connection. When an invalidated `ResultRange`
	is used, a `mysql.exceptions.MYXInvalidatedRange` is thrown. If you need to
	send the server another command, but still access these results afterwords,
	you can save the results for later by converting this range to an array via
	$(LINK2 https://dlang.org/phobos/std_array.html#array, `std.array.array()`).
	+/
	@property bool isValid() const pure nothrow
	{
		return _con !is null && _commandID == _con.lastCommandID;
	}

	/// Check whether there are any rows left
	@property bool empty() const pure nothrow
	{
		if(!isValid)
			return true;

		return !_con._rowsPending;
	}

	/++
	Gets the current row
	+/
	@property inout(Row) front() pure inout
	{
		ensureValid();
		enforce!MYX(!empty, "Attempted 'front' on exhausted result sequence.");
		return _row;
	}

	/++
	Progresses to the next row of the result set - that will then be 'front'
	+/
	void popFront()
	{
		ensureValid();
		enforce!MYX(!empty, "Attempted 'popFront' when no more rows available");
		_row = _con.getNextRow();
		_numRowsFetched++;
	}

	/++
	Get the current row as an associative array by column name

	Type_Mappings: $(TYPE_MAPPINGS)
	+/
	Variant[string] asAA()
	{
		ensureValid();
		enforce!MYX(!empty, "Attempted 'front' on exhausted result sequence.");
		Variant[string] aa;
		foreach (size_t i, string s; _colNames)
			aa[s] = _row._values[i];
		return aa;
	}

	/// Get the names of all the columns
	@property const(string)[] colNames() const pure nothrow { return _colNames; }

	/// An AA to lookup a column's index by name
	@property const(size_t[string]) colNameIndicies() pure nothrow
	{
		if(_colNameIndicies is null)
		{
			foreach(index, name; _colNames)
				_colNameIndicies[name] = index;
		}

		return _colNameIndicies;
	}

	/// Explicitly clean up the MySQL resources and cancel pending results
	void close()
	out{ assert(!isValid); }
	body
	{
		if(isValid)
			_con.purgeResult();
	}

	/++
	Get the number of rows retrieved so far.
	
	Note that this is not neccessarlly the same as the length of the range.
	+/
	@property ulong rowCount() const pure nothrow { return _numRowsFetched; }
}
