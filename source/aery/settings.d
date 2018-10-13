module aery.settings;

__gshared Settings settings;

struct Settings {
    bool debug_mode = false;

    // Default asset paths
    string css_path = "assets/css";
    string js_path = "assets/js";

    // Authentication settings
    string auth_table = "users";
    string auth_user_field = "username";
    string auth_pass_field = "password";
};