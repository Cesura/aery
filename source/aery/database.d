module aery.database;

import models;

import aery.settings;

import std.stdio;
import std.conv;
import std.variant;
import std.typecons;
import std.traits;
import std.array;
import std.file;
import std.meta;
import std.string;
import std.algorithm;
import std.regex;
import core.stdc.stdlib;

import d2sqlite3;

// Models declarations
alias Model = string[string];
alias ModelsArray = Model[int];
ModelsArray _aery_models;

class DBConnector {
    
private:
    Database db;

    // Check whether a table exists in the database
    bool tableExists(string name) {
        string query = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='" ~ name ~ "';";
        int exists = db.execute(query).oneValue!int;
        if (exists)
            return true;
        
        return false;
    }

    // Add a new table with the given query
    void addTable(string query) {

    }

    // Check if the two given models are equivalent
    bool modelsEqual(Model m1, Model m2) {

        foreach (string key, string value; m1) {
            if (key !in m2 || m1[key] != m2[key])
                return false;
        }
        return true;
    }

    // Convert a DB table to a Model
    Model tableToModel(string name) {

        if (!tableExists(name))
            return null;

        // Get the structure of the table in question
        string query = "SELECT * FROM sqlite_master WHERE type='table' AND name='" ~ name ~ "';";
        Row result = db.execute(query).front();
        
        Model table_model = null;
        table_model["_aery_model_name"] = name;

        string fieldtype = "";
        string fieldname = "";
        string other = "";
        int ai_count = 0;

        // Loop through each field
        foreach (string item; to!string(result[4]).findSplitAfter("(")[1].chomp(")").split(",")) {
            item = item.strip();
            fieldname = item.findSplitBefore(" ")[0];
            other = item[fieldname.length+1 .. $];
            fieldtype = other.findSplitBefore(" ")[0].findSplitBefore("(")[0];

            // Convert the SQL types to D types
            switch (fieldtype) {
                case "VARCHAR":
                case "TEXT":
                    fieldtype = "string";
                    break;
                case "INTEGER":
                    fieldtype = "int";
                    break;
                case "FLOAT":
                    fieldtype = "float";
                    break;
                case "DOUBLE":
                    fieldtype = "double";
                    break;
                case "CHARACTER":
                    fieldtype = "char";
                    break;
                default:
                    break;
            }

            // Add the field to the Model array
            table_model[fieldname] = fieldtype;

            // Check if this field is a primary key
            if (other.indexOf("PRIMARY KEY") > -1) {
                table_model["_aery_primary_key"] = fieldname;
            }

            // Check if this field has an AUTOINCREMENT attribute
            if (other.indexOf("AUTOINCREMENT") > -1) {
                if (ai_count == 0)
                    table_model["_aery_auto_increment"] = fieldname;
                else
                    table_model["_aery_auto_increment_" ~ to!string(ai_count)] = fieldname;

                ai_count++;
            }

        }

        return table_model;
    }

    // Verify the database accurately reflects the user-defined models
    void syncModels() {

        // Mixin for compile-time generated models
        mixin(importModels());
        
        // Get all of the tables in the database as models
        string query = "SELECT * FROM sqlite_master WHERE type='table';";
        ResultRange results = db.execute(query);
        Model[string] table_models;
        foreach (Row row; results) {
            string name = to!string(row[1]);

            // Ignore the built-in sqlite table
            if (name != "sqlite_sequence") {
                table_models[name] = tableToModel(name);
            }
        }

        // Convert local models to a more easily searchable array
        Model[string] local_models;
        for (int i=0; i<_aery_models.length; i++) {
            local_models[_aery_models[i]["_aery_model_name"]] = _aery_models[i];
        }

        // Compare table models and local models, making changes when necessary
        foreach (string model_name, Model model; local_models) {
            
            // Model does not exist in the DB
            if (model_name !in table_models) {

                // Extract primary key
                string pk;
                if ("_aery_primary_key" in model)
                    pk = model["_aery_primary_key"];

                // Extract autoincrement fields
                string[] ai;
                int p;
                string search;
                while (true) {
                    if (p == 0)
                        search = "_aery_auto_increment";
                    else
                        search = "_aery_auto_increment_" ~ to!string(p);

                    if (search in model)
                        ai ~= model[search];
                    else
                        break;
                    p++;
                }

                string query = "CREATE TABLE " ~ model_name ~ " (";

                // Loop through fields (in order of appearance in the struct)
                foreach (string field; local_models[model_name]["_aery_order"].chomp(",").split(",")) {

                    // Ignore built-in types
                    if (!field.startsWith("_")) {
                        query ~= field ~ " ";

                        // Convert the D type to a SQL type
                        switch (local_models[model_name][field]) {
                            case "string":
                                query ~= "VARCHAR(" ~ to!string(settings.default_varchar_length) ~ ")";
                                break;
                            case "int":
                                query ~= "INTEGER";
                                break;
                            case "float":
                                query ~= "FLOAT";
                                break;
                            case "double":
                                query ~= "DOUBLE";
                                break;
                            case "char":
                                query ~= "CHARACTER";
                                break;
                            default:
                                break;
                        }

                        if (field == pk)
                            query ~= " PRIMARY KEY";

                        if (ai.canFind(field))
                            query ~= " AUTOINCREMENT";
                        
                        query ~= ", ";
                    }
                }

                query = query.chomp(", ") ~ ");";

                // Execute query
                try {
                    db.execute(query);
                }
                catch (Exception e) {
                    writeln("Error syncing models");
                    exit(1);
                }

            }

            // Model exists in the DB, update components if necessary
            else {

                

            }

            // Loop through table models, deleting them if the local model no longer exists
            if (settings.drop_unused_models) {
                foreach (string model_name, Model model; table_models) {
                    if (model_name !in local_models) {
                        string query = "DROP TABLE " ~ model_name ~ ";";
                        db.execute(query);
                    }
                }
            }
        }
    }


public:
    this(string dbpath) {
        if (!exists(dbpath)) {
            writeln("Error: specified database does not exist.");
            exit(1);
        }

        this.db = Database(dbpath);
        syncModels();
    }

    // Prepare a SQL statment with the given array of key/value pairs
    Statement prepare(string query, string[string] items) {
        Statement stmt = this.db.prepare(query);
        foreach (string identifier, value; items) {
            stmt.bind(identifier, value);
            query = query.replace(identifier, value);
        }

        if (settings.debug_mode)
            writeln(query);

        return stmt;
    }

    
    // Overloaded fetch() for string queries
    T[ulong] fetch(T) (string query) {
        if (settings.debug_mode)
            writeln(query);

        try {
            return fetchBackend!(T)(db.execute(query));
        }
        catch (Exception e) {

            if (settings.debug_mode)
                writeln("Error: SQL error, returning null object");

            return null;
        }
    }


    // Overloaded fetch() for prepared statements
    T[ulong] fetch(T) (Statement stmt) {
        try {
            return fetchBackend!(T)(stmt.execute());
        }
        catch (Exception e) {

            if (settings.debug_mode)
                writeln("Error: SQL error, returning null object");

            return null;
        }
    }

    // Fetch an array of structs for the given query, using the models
    T[ulong] fetchBackend(T) (ResultRange results) {

        T[ulong] return_array;

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
    Database getHandle() {
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

// Invoked by our mixin to populate our models array using the contents of models.d
static string importModels() {
    string contents = import("models.d").replace("\x0a", " ").replace("(\\r*\\n*\\s*)+", " ");
    string return_string = "";

    ModelsArray models;

    // Lots of flags/value stores
    bool skip = false;
    bool rule = false;
    bool newmodel = false;
    bool field = false;
    string type = "";
    string inquestion = "";
    Model model = null;
    int model_count = 0;
    string order;

    // Parse the models.d file
    foreach (string phrase; contents.split(" ")) {
        phrase = phrase.strip();

        // Skip the module declaration/remaining whitespace
        if (phrase == "module" || phrase == "models;"
            || phrase == "" || phrase == " ")
                skip = true;

        if (!skip) {
            
            if (phrase == "//")
                rule = true;
            else if (phrase == "struct")
                newmodel = true;
            else if (phrase == "{")
                continue;
            else if (phrase == "}") {
                model["_aery_order"] = order;
                models[model_count] = model;

                order = "";
                model = null;
                model_count++;
            }
            else if (rule && phrase.startsWith("@")) {
                inquestion = phrase.chompPrefix("@");
            }
            else if (rule && inquestion != "") {
                switch (phrase) {
                    case "auto_increment":
                        
                        string test = "_aery_auto_increment";
                        int p = 1;
                        while (test in model) {
                            test = "_aery_auto_increment_" ~ to!string(p);
                            p++;
                        }
                        
                        model[test] = inquestion;
                        rule = false;
                        break;

                    case "primary_key":
                        model["_aery_primary_key"] = inquestion;
                        rule = false;
                        break;

                    default:
                        break;
                }
                
                rule = false;
                inquestion = "";
            }
            else if (newmodel) {
                model["_aery_model_name"] = phrase;
                newmodel = false;
            }
            else if (!field) {
                type = phrase;
                field = true;
            }
            else if (field) {
                model[phrase.chomp(";")] = type;
                order ~= phrase.chomp(";") ~ ",";
                type = "";
                field = false;
            }
        }
        else
            skip = false;
    }

    // Convert models to a string to be returned to the mixin
    for (int i; i<models.length; i++) {
        return_string ~= "_aery_models[" ~ to!string(i) ~ "] = [";
        foreach (string key, string value; models[i]) {
            return_string ~= "\"" ~ key ~ "\":" ~ "\"" ~ value ~ "\",";
        }

        return_string ~= "];";
    }

    return return_string;
}