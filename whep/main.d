module main;

import whep_client;
import std.stdio : writeln;

void main() {
    writeln("Initializing D-Language WHEP topology pipeline...");

    // Setup configuration definitions for Bob
    string endpoint = "https://your-whip-server.com";
    string token = "super_secure_bob_token_456";

    auto client = new BobWHEPClient(endpoint, token);
    
    // Begin the consumer session lifecycle to receive Alice's stream
    client.startReceiving();
}
