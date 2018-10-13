module aery.templating;

import aery.settings;
import aery.database;

import std.stdio;
import std.file;
import std.string;
import std.conv;
import std.variant;
import std.regex;
import std.algorithm;
import std.array;
import std.traits;
import core.stdc.stdlib;

alias ParamElement = Variant;

// Render a static template given a CachedTemplate object
string renderStatic(CachedTemplate tmp) {
    return tmp.get_contents();
}

// Render a static template given a template path
string renderStatic(string template_path) {
    CachedTemplate tmp = new CachedTemplate(template_path);
    string output = tmp.get_contents();
    destroy(tmp);
    return output;
}

// Render a dymamic template given a CachedTemplate object
string renderTemplate(CachedTemplate tmp, Variant[string] params) {
    return renderTemplateBackend(tmp.get_path(), tmp.get_contents(), params);
}

// Render a dymamic template given a template path
string renderTemplate(string template_path, Variant[string] params) {
    CachedTemplate tmp = new CachedTemplate(template_path);
    string output = renderTemplateBackend(template_path, tmp.get_contents(), params);
    destroy(tmp);
    return output;
}

// Backend to dynamic template rendering functions
string renderTemplateBackend(string template_path, string contents, Variant[string] params) {

    try {
        // Extract all of the values
        string value;
        foreach (m; matchAll(contents, regex(r"\{\{.+?\}\}","m"))) {
            value = strip(strip(strip(m.hit, "{"), "}"));
            
            if (value in params)
                contents = replace(contents, m.hit, to!string(params[value]));
        }

        // Extract all logic operations
        foreach (m; matchAll(contents, regex(r"\{%.+?%\}","m"))) {
            value = strip(strip(strip(strip(strip(m.hit, "{"), "}"), "%")));
            
            string[] elements = split(value, " ");
            switch (elements[0]) {

                // CSS file
                case "css":
                    string path = settings.css_path ~ "/" ~ elements[1];
                    if (!exists(path))
                        path = elements[1];
                    
                    contents = replace(contents, 
                            m.hit, "<link rel=\"stylesheet\" type=\"text/css\" href=\"" 
                            ~ path ~ "\" />");
                    break;

                // Javascript file
                case "js":
                    string path = settings.js_path ~ "/" ~ elements[1];
                    if (!exists(path))
                        path = elements[1];
                    
                    contents = replace(contents,
                        m.hit, "<script src=\"" ~ path ~ "\"></script>");
                    break;

                // If statement
                case "if":

                    bool result;
                    bool invert = false;
                    bool is_else = false;

                    // Boolean
                    if (elements.length == 2) {
                        
                        if (elements[1][0] == '!') {
                            invert = true;
                            elements[1] = strip(elements[1], "!");
                        }
                            

                        if (elements[1] in params) {
                            result = false;
                            if (params[elements[1]].get!(bool))
                                result = true;
                            

                            if (invert)
                                result ^= invert;
                            
                        }
                    }
                    
                    // Comparison
                    else if (elements.length == 4) {
                        
                        Variant first, second;

                        // Convert the expression to the left of the operator 
                        if ((startsWith(elements[1], "\"") && endsWith(elements[1], "\""))
                                || (startsWith(elements[1], "\'") && endsWith(elements[1], "\'"))) {

                            first = elements[1][1..(elements[1].length-1)];

                        }
                        else if (!isNumeric(elements[1])) {

                            if (elements[1] in params)
                                first = params[elements[1]];
                            else
                                throw new Exception("Parse error");
                        }
                        else
                            first = to!float(elements[1]);


                        // Convert the expression to the right of the operator
                        if ((startsWith(elements[3], "\"") && endsWith(elements[3], "\""))
                                || (startsWith(elements[3], "\'") && endsWith(elements[3], "\'"))) {

                            second = elements[3][1..(elements[3].length-1)];

                        }
                        else if (!isNumeric(elements[3])) {
                            if (elements[3] in params)
                                second = params[elements[3]];
                            else
                                throw new Exception("Parse error");
                        }
                        else
                            second = to!float(elements[3]);

                        // Determine what to do based on operator
                        switch (elements[2]) {

                            case "==":
                                result = (first == second) ? true : false;
                                break;
                            
                            case "!=":
                                result = (first != second) ? true : false;
                                break;

                            case ">":
                                result = (first > second) ? true : false;
                                break;
                            
                            case "<":
                                result = (first < second) ? true : false;
                                break;
                            
                            case ">=":
                                result = (first >= second) ? true : false;
                                break;

                            case "<=":
                                result = (first <= second) ? true : false;
                                break;

                            default:
                                throw new Exception("Parse error");
                        }
                    }

                    if (indexOf(contents, "{% else %}") < indexOf(contents, "{% endif %}"))
                        is_else = true;
                    
                    
                    auto before_if = findSplitBefore(contents, m.hit);

                    // Result was not true
                    if (!result) {

                        // There's an else statement; print its contents
                        if (is_else) {
                            auto after_else = findSplitAfter(contents, "{% else %}");
                            auto after_endif = findSplitAfter(contents, "{% endif %}");
                            contents = replaceFirst(before_if[0] ~ after_else[1] ~ after_endif[1], "{% endif %}", "");
                        
                        }

                        // End normally
                        else {
                            auto after_endif = findSplitAfter(contents, "{% endif %}");
                            contents = before_if[0] ~ after_endif[1];
                            
                        }
                        
                    }
                    else {

                        // There's an else statement; ignore it
                        if (is_else) {
                            auto before_else = findSplitBefore(contents, "{% else %}");
                            auto after_endif = findSplitAfter(contents, "{% endif %}");
                            contents = replaceFirst(replaceFirst(before_else[0], m.hit, "") ~ after_endif[1], "{% endif %}", "");
                        }
                        else
                            contents = replaceFirst(replaceFirst(contents, m.hit, ""), "{% endif %}", "");
                    }

                    break;
                
                case "foreach":
                    if (elements.length != 4 || elements[2] != "as")
                        throw new Exception("Parse error");
                    else {
                        if (elements[1] in params) {

                            string prefix = findSplitBefore(elements[3], ".")[0];

                            auto after_foreach = findSplitAfter(contents, "{% foreach " ~ elements[1] ~ " as " ~ elements[3] ~ " %}");
                            auto before_endforeach = findSplitBefore(after_foreach[1], "{% endforeach %}");

                            if (after_foreach[0] == "")
                                break;

                            string stmt_body = before_endforeach[0];
                            string result = "";

                            bool skipnext;
                            foreach (ParamElement x; params[elements[1]]) {
                                skipnext = false;
                                result = result ~ stmt_body;

                                // Loop through all identifiers that specify values of an associative array
                                foreach (n; matchAll(stmt_body, regex(r"(\{\{ )([^\s]+)[.]([^\s]+)( \}\})","m"))) {

                                    auto key = findSplitBefore(findSplitAfter(n.hit, ".")[1], " ")[0];

                                    // Ensure it's the right identifier
                                    if (n.hit.canFind(prefix)) {
                                        result = replace(result, n.hit, to!string(x[key]));
                                        skipnext = true;
                                    }
                                    else
                                        throw new Exception("Parse error");

                                }

                                // Do a regular replacement (assuming it's a single value)
                                if (!skipnext)
                                    result = replace(result, "{{ " ~ elements[3] ~ " }}", to!string(x));
                            }
                            
                            // Do the replacement, and strip the logical operators
                            contents = replaceFirst(replaceFirst(replaceFirst(contents, m.hit, ""), "{% endforeach %}", ""), stmt_body, result);
                        }
                    }
                    break;

                default:
                    break;
            }
        }
    }
    catch (Exception e) {
        writeln(e.msg);
        exit(1);
    }

    return contents;
}

// Object for containing template parameters
class TemplateParams {

private:
    ParamElement[string] params;

public:   
    this() { }
    
    // Catch-all (requires casting)
    void add(string identifier, ParamElement value) { this.params[identifier] = value; }
    void add(string identifier, DBResults value) { this.params[identifier] = value; }

    void add(string identifier, string value) { this.params[identifier] = value; }
    void add(string identifier, string[] value) { this.params[identifier] = value; }
    void add(string identifier, int value) { this.params[identifier] = value; }
    void add(string identifier, int[] value) { this.params[identifier] = value; }
    void add(string identifier, float value) { this.params[identifier] = value; }
    void add(string identifier, float[] value) { this.params[identifier] = value; }
    void add(string identifier, bool value) { this.params[identifier] = value; }
    void add(string identifier, bool[] value) { this.params[identifier] = value; }
   

    auto send() {
        return this.params;
    }
}

// Object for caching templates in memory, rather than reading from the disk on each request
class CachedTemplate {

private:
    string contents;
    string template_path;

public:
    this(string template_path) {
        try {
            this.template_path = template_path;
            this.contents = readText(template_path);
        }
        catch (FileException e) {
            writeln("Error: could not open template '" ~ template_path ~ "'");
            exit(1);
        }
        
    }

    string get_path() {
        return this.template_path;
    }

    string get_contents() {
        return this.contents;
    }
}

// Object for storing templates in memory
class TemplatePool {

private:
    CachedTemplate[string] templates;

public:
    this() {}

    void add(CachedTemplate tmp) {
        this.templates[tmp.get_path()] = tmp;
    }

    CachedTemplate get(string identifier) {
        return this.templates[identifier];
    }
}