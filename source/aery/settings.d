module aery.settings;

__gshared Settings settings;

struct Settings {

    // General settings
    bool debug_mode = false;
    string domain = "127.0.0.1";

    // Default asset paths
    string css_path = "assets/css";
    string js_path = "assets/js";

    // Authentication settings
    string auth_table = "users";
    string auth_user_field = "username";
    string auth_session_dir = "/tmp/.aery_session";

    // Database settings
    int default_varchar_length = 64;
    bool drop_unused_models = true;
    bool create_missing_db = true;
};