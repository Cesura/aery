module aery.database;

import std.stdio;
import std.conv;
import std.variant;
import std.typecons;

import d2sqlite3;
import std.typecons : Nullable;

import aery.settings;

alias DBResults = Variant[ulong]; 

class DBConnector {
    
private:
    Database db;

public:
    this(string dbpath) {
        this.db = Database(dbpath);
    }

    DBResults fetch(string query) {

        if (settings.debug_mode)
            writeln(query);

        ResultRange results = db.execute(query);
        DBResults return_array = null;

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

    void close() {
        this.db.close();
    }


}