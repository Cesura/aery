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
import core.thread;

import mysql;

// Models declarations
alias Model = string[string];
alias ModelsArray = Model[int];
ModelsArray _aery_models;

class DBConnector {
    
private:
    string host;
    int port;
    string user;
    string password;
    string dbname;
    Connection handle;

    // Check whether a table exists in the database
    bool tableExists(string name) {
        MetaData md = MetaData(this.handle);
        auto tables = md.tables();

        if (tables.canFind(name))
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
        ResultRange results = this.handle.query("DESCRIBE " ~ name ~ ";");

        Model table_model = null;
        table_model["_aery_model_name"] = name;

        string fieldtype = "";
        string fieldname = "";
        int ai_count = 0;

        // Loop through each field
        foreach (Row row; results) {
            fieldname = to!string(row[0]);
            fieldtype = convertToDType(to!string(row[1]).findSplitBefore(" ")[0].findSplitBefore("(")[0]);           

            // Add the field to the Model array
            table_model[fieldname] = fieldtype;

            // Check if this field is a primary key
            if (row[3] == "PRI") {
                table_model["_aery_primary_key"] = fieldname;
            }

            // Check if this field has an auto_increment attribute
            if (row[5] == "auto_increment") {
                if (ai_count == 0)
                    table_model["_aery_auto_increment"] = fieldname;
                else
                    table_model["_aery_auto_increment_" ~ to!string(ai_count)] = fieldname;

                ai_count++;
            }

        }

        return table_model;
    }

    string convertToDType(string sql_type) {
        switch (sql_type) {
                case "varchar":
                case "text":
                    return "string";
                default:
                    return sql_type;
            }
    }

    string convertToSQLType(string d_type) {
        switch (d_type) {
            case "string":
                return "varchar(" ~ to!string(settings.default_varchar_length) ~ ")";
            default:
                return d_type;
        }
    }

    // Verify the database accurately reflects the user-defined models
    void syncModels() {

        // Mixin for compile-time generated models
        mixin(importModels());

        Model[string] table_models;
        Model[string] local_models;

        // Get all of the tables in the database as models
        MetaData md = MetaData(this.handle);
        auto tables = md.tables();
        foreach (table; tables) {
            table_models[table] = tableToModel(table);
        }

        // Convert local models to a more easily searchable array
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
                                query ~= "varchar(" ~ to!string(settings.default_varchar_length) ~ ")";
                                break;
                            default:
                                query ~= local_models[model_name][field];
                                break;
                        }

                        if (field == pk)
                            query ~= " PRIMARY KEY";

                        if (ai.canFind(field))
                            query ~= " AUTO_INCREMENT";
                        
                        query ~= ", ";
                    }
                }

                query = query.chomp(", ") ~ ");";

                // Execute query
                try {
                    this.handle.exec(query);
                }
                catch (Exception e) {
                    writeln("Error: could not sync models");
                    exit(1);
                }
            }

            // Model exists in the DB, update components if necessary
            else {

                foreach (string key, string value; model) {

                    // Field does not exist in the DB
                    if (key !in table_models[model_name]) {
                        
                        if (key.length >= 6 && key.startsWith("_aery_"))
                            continue;

                        // Add the new column to the DB table
                        string query = "ALTER TABLE " ~ model_name ~ " ADD COLUMN "
                                        ~ key ~ " " ~ convertToSQLType(value) ~ ";";
                        
                        // Execute query
                        try {
                            this.handle.exec(query);
                        }
                        catch (Exception e) {
                            writeln("Error: could not sync models");
                            exit(1);
                        }
                   
                    }

                    // DB field does not match the local model field
                    else if (local_models[model_name][key] != table_models[model_name][key]) {


                    }
                }
            }

            // Check if there are any fields that exist in the table but not in the local model
            foreach (string column, string type; table_models[model_name]) {
                
                if (column !in local_models[model_name]) {
                        
                        // Drop the column from the DB table
                        string query = "ALTER TABLE " ~ model_name ~ " DROP COLUMN " ~ column ~ ";";
                        
                        // Execute query
                        try {
                            this.handle.exec(query);
                        }
                        catch (Exception e) {
                            writeln("Error: could not sync models");
                            exit(1);
                        }
                }
            }

            // Loop through table models, deleting them if the local model no longer exists
            if (settings.drop_unused_models) {
                foreach (string model_name, Model model; table_models) {
                    if (model_name !in local_models) {
                        string query = "DROP TABLE " ~ model_name ~ ";";
                        this.handle.exec(query);
                    }
                }
            }
        }
    }


public:

    // Use the default values from settings.d
    this() {
        this(settings.mysql_host, settings.mysql_port,
            settings.mysql_user, settings.mysql_pass, settings.mysql_dbname);
    }

    // User passed parameters is value
    this(string host, int port, string user, string password, string dbname) {
        this.host = host;
        this.port = port;
        this.user = user;
        this.password = password;
        this.dbname = dbname;

        this.handle = new Connection("host=" ~ this.host
                                    ~ ";port=" ~ to!string(this.port)
                                    ~ ";user=" ~ this.user
                                    ~ ";pwd=" ~ this.password
                                    ~ ";db=" ~ this.dbname);

        syncModels();
    }

  
    // Overloaded fetch() for string queries
    T[ulong] fetch(T) (string query) {
        return this.fetchBackend!(T)(this.handle.query(query));
    }


    // Overloaded fetch() for prepared statements
    T[ulong] fetch(T) (Prepared stmt) {
        return this.fetchBackend!(T)(this.handle.query(stmt));
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
        ulong return_index = 0;
        foreach (Row row; results) {
            T return_object;

            // Loop through columns
            for (int j=0; j<row.length; j++) {
                int p = 0;
                foreach (field_type; RepresentationTypeTuple!T) {

                    // Check if the column name matches a field name, 
                    // and assign the proper type if it does
                    if (results.colNames[j] == field_names[p]) {

                        // If it's a string and also null, choose an empty string instead
                        if (is(field_type == string) && row[j] == null)
                            return_object.setValue(results.colNames[j], "");
                        else
                            return_object.setValue(results.colNames[j], row[j].get!(field_type));
                        
                        break;
                    }

                    p++;
                }
            }

            return_array[return_index++] = return_object;
        }

        return return_array;
    }

    // Return a prepared statement
    Prepared prepare(string query) {
        return this.handle.prepare(query);
    }

    // Return a pointer to this DB instance
    Connection getHandle() {
        return this.handle;
    }

    // Close the connection (the garbage collector will most likely do this)
    void close() {
        this.handle.close();
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