module whep_client;

import std.stdio : writeln;
import std.net.curl : HTTP, post, patch;
import std.experimental.logger;

// Stub structural interfaces matching your D WebRTC environment 
// (e.g., binding to libdatachannel, native systems, or WebAssembly)
extern(C) {
    struct RTCIceCandidate {
        string candidate;
        string sdpMid;
        int sdpMLineIndex;
    }

    struct RTCSessionDescription {
        string type;
        string sdp;
    }

    class RTCPeerConnection {
        // WHEP client explicitly requests media tracks rather than publishing them
        void addTransceiver(string type, string direction) {} 
        RTCSessionDescription createOffer() { 
            return RTCSessionDescription("offer", "v=0\r\no=- ...\r\na=recvonly\r\n"); 
        }
        void setLocalDescription(RTCSessionDescription desc) {}
        void setRemoteDescription(RTCSessionDescription desc) {}
        void close() {}
        
        // Callback handlers
        void delegate(RTCIceCandidate) onIceCandidate;
        void delegate(string) onIceConnectionStateChange;
        void delegate(string trackId) onTrack; // Triggered when Alice's stream arrives
    }
}

class BobWHEPClient {
private:
    string whepUrl;
    string bearerToken;
    string resourceUrl;
    RTCPeerConnection pc;

public:
    this(string whepUrl, string bearerToken = "") {
        this.whepUrl = whepUrl;
        this.bearerToken = bearerToken;
    }

    void startReceiving() {
        // 1. Initialize PeerConnection
        this.pc = new RTCPeerConnection();
        
        // Configure to only receive Audio and Video from Alice
        this.pc.addTransceiver("audio", "recvonly");
        this.pc.addTransceiver("video", "recvonly");

        // 2. Event: Handle remote tracks coming in from Alice
        this.pc.onTrack = (string trackId) {
            infof("Success! Bob received Alice's media track: %s", trackId);
            // Connect trackId to Bob's local media rendering pipeline/player here
        };

        // 3. Event: Set up Trickle ICE handler
        this.pc.onIceCandidate = (RTCIceCandidate candidate) {
            if (candidate.candidate.length == 0) return; // End of candidates

            // If we have a session endpoint from the WHEP server, trickle the candidate
            if (this.resourceUrl.length > 0) {
                this.sendTrickleCandidate(candidate);
            }
        };

        // 4. Event: Track Connection Failures between nodes
        this.pc.onIceConnectionStateChange = (string state) {
            infof("Bob's ICE Connection State: %s", state);
            if (state == "failed") {
                this.handleConnectionFailure("ICE connection failed between WHEP server and Bob.");
            }
        };

        try {
            // 5. Create Local SDP Offer (Requesting Alice's stream via recvonly configuration)
            RTCSessionDescription offer = this.pc.createOffer();
            this.pc.setLocalDescription(offer);

            // 6. Build HTTP Handshake Request
            auto http = HTTP(this.whepUrl);
            http.addRequestHeader("Content-Type", "application/sdp");
            if (this.bearerToken.length > 0) {
                http.addRequestHeader("Authorization", "Bearer " ~ this.bearerToken);
            }

            // Extract the session tracking Location header for continuous signaling (Trickle ICE / Disconnect)
            http.onReceiveHeader = (string key, string value) {
                if (key.length >= 8 && key[0..8] == "Location") {
                    this.resourceUrl = value;
                }
            };

            // 7. Request the egress stream via HTTP POST
            infof("Connecting Bob to WHEP server endpoint: %s", this.whepUrl);
            char[] responseSdp = post(this.whepUrl, offer.sdp, http);

            if (http.statusLine.code != 201 && http.statusLine.code != 200) {
                throw new Exception("WHEP server rejected playback request. HTTP Code: " ~ http.statusLine.code);
            }

            // Fallback resource assignment if header paths are relative or blank
            if (this.resourceUrl.length == 0) {
                this.resourceUrl = this.whepUrl;
            }

            // 8. Apply Remote SDP Answer containing Alice's structural media descriptions
            RTCSessionDescription answer = RTCSessionDescription("answer", cast(string)responseSdp);
            this.pc.setRemoteDescription(answer);

            infof("Initial WHEP session established. Resource URL allocated for signaling: %s", this.resourceUrl);

        } catch (Exception e) {
            this.handleConnectionFailure(e.msg);
        }
    }

    // Sends Bob's Trickle ICE signals through the WHEP server to Alice
    void sendTrickleCandidate(RTCIceCandidate candidate) {
        if (this.resourceUrl.length == 0) return;

        // RFC compliant minimal SDP fragment format
        string sdpFragment = "candidate:" ~ candidate.candidate ~ "\r\n";

        try {
            auto http = HTTP(this.resourceUrl);
            http.method = HTTP.Method.patch;
            http.addRequestHeader("Content-Type", "application/trickle-ice-sdpfrag");
            if (this.bearerToken.length > 0) {
                http.addRequestHeader("Authorization", "Bearer " ~ this.bearerToken);
            }

            infof("Trickling Bob's ICE candidate to WHEP router...");
            patch(this.resourceUrl, sdpFragment, http);

        } catch (Exception e) {
            errorf("Network failure during Bob's Trickle ICE PATCH execution: %s", e.msg);
        }
    }

    // Gracefully handles connection failure routes
    void handleConnectionFailure(string reason) {
        errorf("Topology Routing Error Triggered: %s", reason);
        if (this.pc !is null) {
            this.pc.close();
        }
        writeln("Alert: Bob's WHEP media receive pipeline was aborted.");
    }
}
