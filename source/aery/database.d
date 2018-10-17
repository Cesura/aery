module aery.database;

import aery.settings;

import std.stdio;
import std.conv;
import std.variant;
import std.typecons;
import std.traits;
import std.meta;

import d2sqlite3;

class DBConnector {
    
private:
    Database db;

public:
    this(string dbpath) {
        this.db = Database(dbpath);
    }

    // Fetch an array of structs for the given query, using the models
    T[ulong] fetch(T) (string query) {

        T[ulong] return_array;

        if (settings.debug_mode)
            writeln(query);

        ResultRange results = db.execute(query);

        // Get a tuple of the field names for T and make it an array
        auto fields_tuple = FieldNameTuple!T;
        string[int] field_names;
        int n = 0;
        foreach (string field_name; fields_tuple) {
            field_names[n] = field_name;
            n++;
        }

        // Loop through rows
        bool found = false;
        ulong return_index = 0;
        foreach (Row row; results) {
            T return_object;

            // Loop through columns
            for (int j=0; j<row.length; j++) {
                
                int p = 0;
                foreach (field_type; RepresentationTypeTuple!T) {
                    if (found)
                        break;

                    // Check if the column name matches a field name, 
                    // and assign the proper type if it does
                    if (row.columnName(j) == field_names[p]) {
                        return_object.setValue(row.columnName(j), row[j].as!(field_type));
                        found = true;
                    }

                    p++;
                }

                found = false;                
            }
            
            return_array[return_index] = return_object;
            return_index++;
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

// Set a template value V in a template struct T
static void setValue(T, V)(auto ref T structure, string field, V value) {
    switch (field) {
        foreach (fieldName; FieldNameTuple!T) {
            case fieldName:
                static if (is(typeof(__traits(getMember, structure, fieldName) = value))) {
                    __traits(getMember, structure, fieldName) = value;
                    return;
                }
        }
        default:
            break;
    }
}