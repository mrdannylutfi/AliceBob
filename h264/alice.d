import std.stdio;
import std.string;
import std.c.string : memset;

// D bindings matching the uvgRTP C++ interface
extern (C++, "uvgrtp") {
    enum rtp_format_t {
        RTP_FORMAT_GENERIC = 0,
        RTP_FORMAT_H264    = 1,
        RTP_FORMAT_OPUS    = 2
    }

    enum rtp_flags_t {
        RTP_NO_FLAGS = 0
    }

    enum rtp_ctx_flags_t {
        RCE_NO_FLAGS     = 0,
        RCE_FRAGMENT_AVC = 1 << 0
    }

    enum rtp_error_t {
        RTP_OK = 0
    }

    extern (C++, "frame") {
        struct rtp_frame {
            size_t payload_len;
            uint8_t* payload;
            // Other internal struct fields omitted for clarity
        }
        void dealloc_frame(rtp_frame* frame);
    }

    interface media_stream {
        rtp_error_t push_frame(const(uint8_t)* data, size_t data_len, int flags);
        rtp_frame* pull_frame();
    }

    interface session {
        media_stream* create_stream(ushort local_port, ushort remote_port, rtp_format_t fmt, int flags);
    }

    class context {
        this();
        session* create_session(const(char)* address);
        rtp_error_t destroy_session(session* session);
    }
}

int main() {
    // 1. Initialize the global uvgRTP Context
    auto ctx = new uvgrtp.context();

    // Define Bob's Destination IP address
    string bobs_ip = "192.168.1.100";

    // 2. Create a Session with Bob
    writeln("[Alice] Initializing session with Bob at ", bobs_ip, "...");
    auto sess = ctx.create_session(bobs_ip.toStringz());
    if (!sess) {
        stderr.writeln("Failed to create uvgRTP session.");
        return 1;
    }

    // 3. Generate & Create the Opus Audio Stream
    writeln("[Alice] Generating Opus audio stream channel...");
    auto opus_strm = sess.create_stream(8890, 8890, uvgrtp.rtp_format_t.RTP_FORMAT_OPUS, uvgrtp.rtp_ctx_flags_t.RCE_NO_FLAGS);

    // 4. Create the H.264 Video Stream
    writeln("[Alice] Generating H.264 video stream channel...");
    auto h264_strm = sess.create_stream(8888, 8888, uvgrtp.rtp_format_t.RTP_FORMAT_H264, uvgrtp.rtp_ctx_flags_t.RCE_FRAGMENT_AVC);

    if (!opus_strm || !h264_strm) {
        stderr.writeln("Error creating media streams.");
        ctx.destroy_session(sess);
        return 1;
    }

    // --- Data Phase ---

    // Simulated H.264 video keyframe data buffer
    uint8_t[1024] dummy_h264_frame;
    memset(dummy_h264_frame.ptr, 0xAB, dummy_h264_frame.sizeof);

    // 5. Send the H.264 frame to Bob
    writeln("[Alice] Sending H.264 video data payload to Bob...");
    auto send_err = h264_strm.push_frame(dummy_h264_frame.ptr, dummy_h264_frame.sizeof, uvgrtp.rtp_flags_t.RTP_NO_FLAGS);

    if (send_err != uvgrtp.rtp_error_t.RTP_OK) {
        stderr.writeln("Failed to push H.264 frame. Error code: ", send_err);
    } else {
        writeln("[Alice] Video packet transmitted successfully. Awaiting Bob's confirmation...");

        // 6. Await Bob's Application-level Confirmation Frame
        // This blocks here until a packet returns via port 8888
        uvgrtp.frame.rtp_frame* confirmation_frame = h264_strm.pull_frame();

        if (confirmation_frame) {
            writeln("[Alice] Confirmation received from Bob!");
            writeln("-> Received Payload Size: ", confirmation_frame.payload_len, " bytes.");

            // Convert raw confirmation bytes back into a D string slice
            auto msg = (cast(char*)confirmation_frame.payload)[0 .. confirmation_frame.payload_len];
            writeln("-> Bob's message: \"", msg, "\"");

            // Always free memory allocated for pulled frames manually
            uvgrtp.frame.dealloc_frame(confirmation_frame);
        } else {
            writeln("[Alice] Warning: Awaiting frame timed out or socket closed without confirmation.");
        }
    }

    // 7. Cleanup session resources safely
    writeln("[Alice] Closing active stream sockets...");
    ctx.destroy_session(sess);

    return 0;
}
