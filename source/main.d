import std.stdio;
import std.conv;
import std.traits;
import std.variant;

import std.typecons;

import aery.all;

import models;

__gshared TemplatePool pool;
__gshared DBConnector db;

void main() {

    Router router = new Router();
    router.add("/", &homePage);
    router.add(POST, "/login", &login);
    router.add("/logout", &logout);

    settings.debug_mode = true;

    pool = new TemplatePool();
    pool.add(new CachedTemplate("templates/template.html"));

    db = new DBConnector("./database.db");

    listen(8081, router);
    db.close();
}

void homePage(HTTPRequest req, HTTPResponse res) {

    TemplateParams params = new TemplateParams();

    if (req.logged_in()) {
        auto users = db.fetch!(User)("SELECT * FROM users;");
        params.addModels("users", users);

        params.add("logged_in", true);
        params.add("header", req.session.get("username"));
        params.add("title", "User zone");
    }
    else {
        params.add("logged_in", false);
        params.add("header", "Please log in");
        params.add("title", "Login zone");
    }
    

    res.send(renderTemplate(pool.get("templates/template.html"), params.send()));
}

void login(HTTPRequest req, HTTPResponse res) {
    
    string username = req.form("username");
    string password = req.form("password");

    Authenticator a = new Authenticator(db);

    if (a.verify(username, password, res)) {
        res.redirect("/");
    }
    else {
        res.redirect("/?error");
    }
}


void logout(HTTPRequest req, HTTPResponse res) {
    req.session.destroy();
    res.redirect("/");
}