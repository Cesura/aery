module aery.settings;

__gshared Settings settings;

struct Settings {

    // General settings
    bool debug_mode = false;
    string domain = "127.0.0.1";

    // Default asset paths
    string css_path = "assets/css";
    string js_path = "assets/js";

    // Database connection settings
    string mysql_host = "localhost";
    int mysql_port = 3306;
    string mysql_user = "root";
    string mysql_pass = "password";
    string mysql_dbname = "testdb";

    // Authentication settings
    string auth_table = "User";
    string auth_user_field = "username";
    string auth_session_dir = "/tmp/.aery_session";

    // Session settings
    int session_length = 3600;              // in seconds

    // Database settings
    int default_varchar_length = 64;
    bool drop_unused_models = true;
    bool create_missing_db = true;
};