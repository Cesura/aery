import std.stdio;
import std.conv;
import std.variant;

import aery.all;

__gshared TemplatePool pool;

void main() {

    Router router = new Router();
    router.add("/", &homePage);

    settings.debug_mode = true;

    pool = new TemplatePool();
    pool.add(new CachedTemplate("templates/template.html"));

    listen(8080, router);
}

void homePage(HTTPRequest req, HTTPResponse res) {

    TemplateParams params = new TemplateParams();
    params.add("header", "Page Header");
    params.add("title", "Page Title");
    params.add("logged_in", true);

    string[string] user1 = [ "id" : "1", "name" : "Joe"];
    string[string] user2 = [ "id" : "3", "name" : "Bob"];

    params.add("users", to!Variant([user1, user2]));

    res.send(renderTemplate(pool.get("templates/template.html"), params.send()));
}