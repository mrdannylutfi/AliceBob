module main;

import whip_client;
import std.stdio : writeln;

void main() {
    writeln("Initializing D-Language WHIP topology pipeline...");

    // Setup configuration definitions 
    string endpoint = "https://your-whip-server.com";
    string token = "super_secure_alice_token_123";

    auto client = new AliceWHIPClient(endpoint, token);
    
    // Simulate beginning the media streaming lifecycle pipeline
    client.startPublishing("camera_track_0");
}
