module aery.authentication;

import models;

import aery.database;
import aery.settings;
import aery.httpserver;

import std.stdio;
import std.digest.sha;
import std.conv;
import std.array;

import mysql;

class Authenticator {

private:
    DBConnector db;
    string auth_table;
    string auth_user_field;

public:
    
    // Use the predefined settings
    this(DBConnector db) {
        this.db = db;
        this.auth_table = settings.auth_table;
        this.auth_user_field = settings.auth_user_field;
    }

    // Explicitly define SQL settings
    this(DBConnector db, string auth_table, string auth_user_field) {
        this.db = db;
        this.auth_table = auth_table;
        this.auth_user_field = auth_user_field;
    }

    // Authenticate a user, only returning true or false
    bool verify(string username, string password) {
        return verify_backend(username, password);
    }

    // Authenticate a user, starting a session for them
    bool verify(string username, string password, HTTPResponse res) {
        if (verify_backend(username, password)) {
            res.session().add("username", username);
            res.session().create();
            res.set_cookie(new Cookie("aery_session", res.session().id()));
            return true;
        }

        return false;
    }

    // Authenticate a user (backend)
    bool verify_backend(string username, string password) {

        // Prepare the query
        string query = "SELECT password FROM " ~ this.auth_table 
            ~ " WHERE " ~ this.auth_user_field ~ "=?;";
    
        Prepared prepared = this.db.prepare(query);
        prepared.setArgs(username);
        auto user = db.fetch!(User)(prepared);

        // There was an finding the right database table/field
        if (user == null) {
            writeln("Error: could not find authentication table/field. Check your settings.d file.");
            return false;
        }

        // The user was not found
        if (user.empty)
            return false;

        if (toHexString(sha256Of(password)) == to!string(user[0].password))
            return true;
        else
            return false;
    }

}