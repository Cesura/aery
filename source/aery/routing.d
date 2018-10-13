module aery.routing;

import std.conv;
import std.array;

import aery.httpserver;

const int GET = 0;
const int POST = 1;

class Router {

private:
    void function(HTTPRequest req, HTTPResponse res)[string][string] callback_array;

    // Backend for adding routes
    void add_backend(string path, string type, 
        void function(HTTPRequest req, HTTPResponse res) callback) {

        this.callback_array[path][type] = callback;
    }

public:
    this() { }

    // Add a new request, defaults to GET
    void add(string path, void function(HTTPRequest req, HTTPResponse res) callback) {
        add_backend(path, "GET", callback);
    }

    // Add a new request (explicit)
    void add(int type, string path, void function(HTTPRequest req, HTTPResponse res) callback) {
        (type == 0) ? add_backend(path, "GET", callback) : add_backend(path, "POST", callback);
    }

    // Return a callback, or null
    void function(HTTPRequest req, HTTPResponse res) get_callback(string type, string path) {
        if (path in this.callback_array)
            if (type in this.callback_array[path])
                return this.callback_array[path][type];
        
        return null;
    }
}
