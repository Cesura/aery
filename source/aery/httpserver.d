module aery.httpserver;

import aery.routing;
import aery.mime;
import aery.settings;
import aery.session;

import std.conv;
import std.stdio;
import std.string;
import std.array;
import std.file;
import std.algorithm;
import std.socket;
import std.concurrency;
import std.uri;
import core.stdc.stdlib;

__gshared Router router;

alias FormData = string[string];

// No address given, assume localhost
void listen(ushort port, Router rt) {
	listen_backend("localhost", port, rt);
}

// Listen on specified address
void listen(string address, ushort port, Router rt) {
	listen_backend(address, port, rt);
}

// Backend for listen() functions
void listen_backend(string address, ushort port, Router rt) {
    
	Socket socket = new TcpSocket();
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	socket.bind(new InternetAddress(port));
	socket.listen(1);

	settings.domain = address;

	if (settings.debug_mode)
		writefln("Listening on %s:%d...", address, port);

	router = rt;

	for (;;) {
		Socket client = socket.accept();
		auto child = spawn(&handleConnection);
		send(child, cast(shared)client);
	}
}

static void handleConnection() {
	
	Socket client;

	receive((shared Socket s){
		client = cast(Socket)s;
	});

	ubyte[4096] buffer;
    auto received = client.receive(buffer);
	
	// Split up HTTP headers into an array
	string request = cast(string)buffer;
	string[] headers = request.split("\r\n");
	string msg_body = findSplitBefore(findSplitAfter(request, "\r\n\r\n")[1], "\0")[0];

	if (settings.debug_mode)
		writeln(headers[0]);

	// fields[0] -> request type
	// fields[1] -> requested path
	// fields[2] -> HTTP version
	string[] fields = headers[0].split(" ");
	
	// If < 3 fields, it's a malformed HTTP request
	if (fields.length >= 3) {
		HTTPRequest req = new HTTPRequest(fields[1]);
		HTTPResponse res = new HTTPResponse(client);

		// Loop through options and see if anything needs to be set
		string[string] options;

		for (int i=1; i<headers.length-1; i++) {
			auto pair = headers[i].findSplit(":");
			options[pair[0]] = pair[2];

			// Handle sent cookies
			if (pair[0] == "Cookie") {
				auto cookies = pair[2].split(";");

				foreach (string cookie; cookies) {
					auto cookie_elements = cookie.strip().findSplit("=");
					if (cookie_elements.length == 3) {
						req.set_cookie(new Cookie(cookie_elements[0], cookie_elements[2]));
					}
				}
				
				
			}
		}

		string request_type = fields[0];
		string request_path = fields[1];

		// Ignore trailing slashes in the request
		if (request_path.length > 1 && request_path[request_path.length-1] == '/')
			request_path.popBack();

		// Handle GET requests
		if (request_type == "GET") {
			void function(HTTPRequest req, HTTPResponse res) callback
				= router.get_callback("GET", request_path);
			
			// Assume it was a static asset request
			if (callback == null) {
				request_path = chompPrefix(request_path, "/");

				if (exists(request_path) && isFile(request_path)) {
					string[] ext = request_path.split(".");

					StaticAsset asset = new StaticAsset(request_path);
					res.send_mime(get_mime(ext[ext.length-1]), asset.get_contents());
				}
				else {
					res.not_found();
				}
			}

			// Otherwise, simply do the callback
			else {
				callback(req, res);
			}
		}

		// Handle POST requests
		else if (request_type == "POST") {

			// Right now we're assuming it's raw form data (will change)
			FormData form_data = parse_form(msg_body);
			if (!(form_data is null))
				req.set_form_data(form_data);

			void function(HTTPRequest req, HTTPResponse res) callback
				= router.get_callback("POST", request_path);
			

			if (callback == null) {
				res.not_found();
			}

			// Otherwise, simply do the callback
			else {
				callback(req, res);
			}

		}
	}

	client.close();
}

// Helper function to parse form data from an HTTP body
static FormData parse_form(string raw) {
	FormData return_array = null;

	foreach (string s; raw.split("&")) {
		auto split = s.findSplit("=");
		return_array[split[0].replace("+", " ").decodeComponent] = split[2].replace("+", " ").decodeComponent;
	}

	return return_array;
}

// An object for containing a static asset
class StaticAsset {

private:
	string path;
	File fp;
	ubyte[] buf;

public:
	this(string path) {
		try {
			fp = File(path, "r");

			if (fp.size > 0)
				buf = fp.rawRead(new ubyte[fp.size]);
				
			fp.close();
		} catch (FileException e) {}
		
	}

	ubyte[] get_contents() {
		return this.buf;
	}
}

// An object representing an HTTP request
class HTTPRequest {

private:
	Socket sock;
	string uri;
	Cookie[string] cookies;
	FormData form_data;
	Session req_session;

public:
	this(string request_uri) {
		this.uri = request_uri;
		this.req_session = new Session();
	}


	// Return a cookie based on the given key, or null
	string cookie(string key) {
		if (key in cookies)
			return this.cookies[key].value();
		return null;
	}

	// Get a pointer to the session given in this request
	Session session() {
		return this.req_session;
	}

	// Extract a form data element based on key
	string form(string key) {
		if (key in this.form_data)
			return this.form_data[key];
		return null;
	}

	// Return the request URI that was taken from the HTTP request
	string request_uri() {
		return this.uri;
	}

	// Return true/false based on whether the given user has a valid session ID
	bool logged_in() {
		if (!this.req_session.valid())
			return false;	
		return true;
	}

	// Set form data for this request (used by server)
	void set_form_data(FormData form_data) {
		this.form_data = form_data;
	}

	// Set a cookie for this request (used by server)
	void set_cookie(Cookie cookie) {
		this.cookies[cookie.key()] = cookie;

		if (cookie.key() == "aery_session") {
			this.req_session = new Session(cookie.value());
		}
	}
}

// An object representing an HTTP response
class HTTPResponse {

private:
	Socket sock;
	Session res_session;
	Cookie[string] cookies;

public:
	this(Socket sock) {
		this.sock = sock;
	}

	// Send a string of characters, rendered as text/html
	void send(string input) {
		string header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: keep-alive\r\n"
			~ this.append_cookies() ~ "\r\n";

		string response = header ~ input;

		sock.send(response);
	}

	// Send a given file and specify the MIME type
	void send_mime(string mime, ubyte[] buf) {
		
		string header = "HTTP/1.1 200 OK\r\nContent-Length: " ~ to!string(buf.length)
			~ "\r\nContent-Type: " ~ mime ~ "\r\nConnection: keep-alive\r\n" 
			~ "Cache-Control: max-age=3600\r\n\r\n";

		sock.send(header);
		sock.send(buf);
	}

	// Produce a 404
	void not_found() {
		enum header = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n";
		string response = header ~ "<html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1></body></html>";
				
		sock.send(response);
	}

	// Append cookies to the HTTP header
	string append_cookies() {
		string return_string = "";
		foreach (Cookie cookie; this.cookies) {
			return_string ~= cookie.http_string();
		}
		return return_string;
	}

	// Redirect to given URL
	void redirect(string url) {
		string header = "HTTP/1.1 302 Found\r\nLocation: " ~ url ~ "\r\n" ~ this.append_cookies() ~ "\r\n";
		sock.send(header);
	}

	// Get a pointer to this session
	Session session() {
		if (this.res_session is null)
			this.res_session = new Session();

		return this.res_session;
	}

	// Set a cookie for this response
	void set_cookie(Cookie cookie) {
		this.cookies[cookie.key()] = cookie;
	}

	// Return a cookie based on the given key, or null
	string cookie(string key) {
		if (key in cookies)
			return this.cookies[key].value();
		return null;
	}

}

// An object representing an HTTP cookie
class Cookie {

private:
	string cookie_key;
	string cookie_value;

public:
	this(string key, string value) {
		this.cookie_key = key;
		this.cookie_value = value;
	}

	// Return the key of this cookie
	string key() {
		return this.cookie_key;
	}
	
	// Return the value of this cookie
	string value() {
		return this.cookie_value;
	}

	// Return a formatted string to be put in an HTTP response header
	string http_string() {
		return "Set-Cookie: " ~ this.cookie_key ~ "=" ~ this.cookie_value 
			~ "; Max-Age=3600; Domain: " ~ settings.domain ~ "\r\n";
	}
}