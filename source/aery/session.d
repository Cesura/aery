module aery.session;

import aery.settings;

import std.stdio;
import std.conv;
import std.file;
import std.array;
import std.random;
import std.digest.md;
import std.random;
import std.datetime;
import core.stdc.stdlib;

class Session {

private:
	string session_id;
	string[string] session_vars;

public:
	// Default constructor, for creating new sessions
	this() { }

	// Initialize this session object with an existing session file
	this(string session_id) {
		this.session_id = session_id;
		string path = settings.auth_session_dir ~ "/" ~ session_id;

		try {
			if (!(session_id is null) && exists(path)) {
				string from_file = readText(path);
				auto lines = from_file.split("\n");

				foreach (string line; lines) {
					auto elements = line.split("=");

					if (elements.length == 2)
						this.add(elements[0], elements[1]);
				}
			}

        }
        catch (FileException e) {
            writeln("Error: could not open session file '" ~ path ~ "'");
            exit(1);
        }
	}

	// Return the ID of this session (the cookie value/file name)
	string id() {
		return this.session_id;
	}

	// Add a new session variable with the given key/value pair
	void add(string key, string value) {
		this.session_vars[key] = value;
	}

	// Return a session variable with the given key
	string get(string key) {
		if (key in this.session_vars)
			return this.session_vars[key];
		return null;
	}

	// Create a new session and session file
	void create() {

		try {
			if (exists(settings.auth_session_dir) && !isDir(settings.auth_session_dir))
				remove(settings.auth_session_dir);

			if (!exists(settings.auth_session_dir))
				mkdir(settings.auth_session_dir);

			auto rng = new Random(unpredictableSeed);
    		auto md5 = new MD5Digest();

			// Generate a random file for the session
			string potential_file = toHexString(md5.digest(to!string(uniform(0, 500000, rng))));
			while (exists(settings.auth_session_dir ~ "/" ~ potential_file)) {
				potential_file = toHexString(md5.digest(to!string(uniform(0, 500000, rng))));
			}


			this.add("_aery_expires", to!string((Clock.currTime()+3600.seconds).toUnixTime));

			// Write the session vars to the new session file
			foreach (string key, string value; this.session_vars) {
				std.file.append(settings.auth_session_dir ~ "/" ~ potential_file, key ~ "=" ~ value ~ "\n");
			}

			this.session_id = potential_file;
        }
        catch (FileException e) {
            writeln("Error: could not open session directory '" ~ settings.auth_session_dir ~ "'");
            exit(1);
        }
	}

	// Destroy the given session (note: does not delete client-side cookie)
	void destroy() {
		string path = settings.auth_session_dir ~ "/" ~ this.session_id;

		try {
			if (exists(path)) {
				remove(path);
				this.session_id = null;
			}
		}
		catch (FileException e) {
            writeln("Error: could not delete session file '" ~ path ~ "'");
            exit(1);
        }
	}

	// Validate that this session exists and has not expired
	bool valid() {
		string path = settings.auth_session_dir ~ "/" ~ this.session_id;

		if (this.session_id is null || !exists(path))
			return false;
		else {
			auto expires = this.get("_aery_expires").to!(long);
			
			if (expires < Clock.currTime().toUnixTime) {
				remove(path);
				return false;
			}
		}

		return true;
	}
}