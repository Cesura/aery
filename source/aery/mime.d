module aery.mime;

string get_mime(string extension) {
    string[string] mime_types = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "bmp": "image/bmp",
        "html": "text/html",
        "css": "text/css",
        "txt": "text/plain",
        "xml": "application/xml",
        "js": "application/x-javascript",
        "pdf": "application/pdf"
    ];

    if (extension in mime_types)
        return mime_types[extension];
    else
        return "application/octet-stream";
}