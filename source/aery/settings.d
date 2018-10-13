module aery.settings;

__gshared Settings settings;

struct Settings {
    bool debug_mode = false;
    string css_path = "assets/css";
    string js_path = "assets/js";
};