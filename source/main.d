import std.stdio;
import std.conv;
import std.concurrency;

import aery.all;

__gshared TemplatePool pool;
__gshared DBConnector db;

void main() {

    Router router = new Router();
    router.add("/", &homePage);

    router.add("/google", &toGoogle);

    settings.debug_mode = false;

    pool = new TemplatePool();
    pool.add(new CachedTemplate("templates/template.html"));

    db = new DBConnector("./database.db");
  
    listen(8080, router);
    db.close();
}

void homePage(HTTPRequest req, HTTPResponse res) {

    TemplateParams params = new TemplateParams();
    params.add("header", req.session().id());
    params.add("title", "Page Title");

    DBResults users = db.fetch("SELECT * FROM users;");

    params.add("users", users);

    res.send(renderTemplate(pool.get("templates/template.html"), params.send()));
}


void toGoogle(HTTPRequest req, HTTPResponse res) {
    res.redirect("https://google.com");
}