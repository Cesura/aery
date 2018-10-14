module aery.database;

import aery.settings;

import std.stdio;
import std.conv;
import std.variant;
import std.typecons;

import d2sqlite3;

alias DBResults = Variant[ulong]; 

class DBConnector {
    
private:
    Database db;

public:
    this(string dbpath) {
        this.db = Database(dbpath);
    }

    // Fetch a DBResults object for the given query
    DBResults fetch(string query) {

        if (settings.debug_mode)
            writeln(query);

        ResultRange results = db.execute(query);
        DBResults return_array = null;

        // Loop through rows
        ulong i = 0;
        foreach (Row row; results) {
            Variant[string] return_object;

            for (int j=0; j<row.length; j++) {
                return_object[row.columnName(j)] = row[j];
            }

            return_array[i] = return_object;
            i++;
        }

        return return_array;
    }

    // Return a pointer to this DB instance
    Database get_handle() {
        return this.db;
    }

    // Close the connection (the garbage collector will most likely do this)
    void close() {
        this.db.close();
    }


}