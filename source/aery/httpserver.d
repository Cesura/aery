module aery.httpserver;

import aery.routing;
import aery.mime;
import aery.settings;

import std.conv;
import std.stdio;
import std.string;
import std.array;
import std.file;
import std.socket;
import std.concurrency;

__gshared Router router;

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
	
	// Split first line of HTTP request into its elements
	string request = "";
	for (int i = 0; i<received; i++) {
		if (buffer[i] == '\n' || buffer[i] == '\r')
			break;

		request ~= buffer[i];
	}

	if (settings.debug_mode)
		writeln(request);

	// fields[0] -> request type
	// fields[1] -> requested path
	// fields[3] -> HTTP version
	string[] fields = request.split(" ");
	
	// If < 3 fields, it's a malformed HTTP request
	if (fields.length >= 3) {
		HTTPRequest req = new HTTPRequest();
		HTTPResponse res = new HTTPResponse(client);

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
	}

	client.close();
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

}

// An object representing an HTTP response
class HTTPResponse {

private:
	Socket sock;

public:
	this(Socket sock) {
		this.sock = sock;
	}

	// Send a string of characters, rendered as text/html
	void send(string input) {
		enum header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n";
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

}