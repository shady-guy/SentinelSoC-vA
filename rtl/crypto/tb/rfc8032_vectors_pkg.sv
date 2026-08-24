// rfc8032_vectors_pkg.sv
// RFC 8032 section 7.1 Known-Answer-Test vectors for Ed25519.
// Only vectors whose message length is a multiple of 4 bytes are usable
// with top_most (design assumes 4-byte-aligned message length):
//   - TEST 1        : message length 0 bytes
//   - TEST SHA(abc) : message length 64 bytes
// (TEST 2 = 1 byte, TEST 3 = 2 bytes, TEST 1024 = 1023 bytes -- NOT usable)
//
// All byte arrays are stored in RFC octet-string order: octets[0] is the
// first byte of the field as printed in the RFC. The sequence layer is
// responsible for packing 4 octets into a CSR word as
//   wdata = {octets[4*i+3], octets[4*i+2], octets[4*i+1], octets[4*i]}
// i.e. wdata[7:0] = octets[4*i] (confirmed convention).

package rfc8032_vectors_pkg;

  typedef struct {
    string              name;
    byte unsigned       r_bytes      [32];
    byte unsigned       s_bytes      [32];
    byte unsigned       pubkey_bytes [32];
    byte unsigned       msg_bytes    [];   // dynamic, sized = msg_len_bytes
    int unsigned        msg_len_bytes;
    bit                 expect_pass;
  } ed25519_vector_t;

  //-------------------------------------------------------------------
  // TEST 1 : message length 0 bytes
  //-------------------------------------------------------------------
  function automatic ed25519_vector_t get_test1();
    ed25519_vector_t v;
    v.name          = "RFC8032_TEST1";
    v.msg_len_bytes = 0;
    v.expect_pass   = 1'b1;
    v.msg_bytes     = new[0];

    v.r_bytes = '{
      8'he5,8'h56,8'h43,8'h00, 8'hc3,8'h60,8'hac,8'h72,
      8'h90,8'h86,8'he2,8'hcc, 8'h80,8'h6e,8'h82,8'h8a,
      8'h84,8'h87,8'h7f,8'h1e, 8'hb8,8'he5,8'hd9,8'h74,
      8'hd8,8'h73,8'he0,8'h65, 8'h22,8'h49,8'h01,8'h55
    };

    v.s_bytes = '{
      8'h5f,8'hb8,8'h82,8'h15, 8'h90,8'ha3,8'h3b,8'hac,
      8'hc6,8'h1e,8'h39,8'h70, 8'h1c,8'hf9,8'hb4,8'h6b,
      8'hd2,8'h5b,8'hf5,8'hf0, 8'h59,8'h5b,8'hbe,8'h24,
      8'h65,8'h51,8'h41,8'h43, 8'h8e,8'h7a,8'h10,8'h0b
    };

    v.pubkey_bytes = '{
      8'hd7,8'h5a,8'h98,8'h01, 8'h82,8'hb1,8'h0a,8'hb7,
      8'hd5,8'h4b,8'hfe,8'hd3, 8'hc9,8'h64,8'h07,8'h3a,
      8'h0e,8'he1,8'h72,8'hf3, 8'hda,8'ha6,8'h23,8'h25,
      8'haf,8'h02,8'h1a,8'h68, 8'hf7,8'h07,8'h51,8'h1a
    };

    return v;
  endfunction

  //-------------------------------------------------------------------
  // TEST SHA(abc) : message length 64 bytes
  //-------------------------------------------------------------------
  function automatic ed25519_vector_t get_test_sha_abc();
    ed25519_vector_t v;
    v.name          = "RFC8032_TEST_SHA_ABC";
    v.msg_len_bytes = 64;
    v.expect_pass   = 1'b1;
    v.msg_bytes     = new[64];

    v.r_bytes = '{
      8'hdc,8'h2a,8'h44,8'h59, 8'he7,8'h36,8'h96,8'h33,
      8'ha5,8'h2b,8'h1b,8'hf2, 8'h77,8'h83,8'h9a,8'h00,
      8'h20,8'h10,8'h09,8'ha3, 8'hef,8'hbf,8'h3e,8'hcb,
      8'h69,8'hbe,8'ha2,8'h18, 8'h6c,8'h26,8'hb5,8'h89
    };

    v.s_bytes = '{
      8'h09,8'h35,8'h1f,8'hc9, 8'hac,8'h90,8'hb3,8'hec,
      8'hfd,8'hfb,8'hc7,8'hc6, 8'h64,8'h31,8'he0,8'h30,
      8'h3d,8'hca,8'h17,8'h9c, 8'h13,8'h8a,8'hc1,8'h7a,
      8'hd9,8'hbe,8'hf1,8'h17, 8'h73,8'h31,8'ha7,8'h04
    };

    v.pubkey_bytes = '{
      8'hec,8'h17,8'h2b,8'h93, 8'had,8'h5e,8'h56,8'h3b,
      8'hf4,8'h93,8'h2c,8'h70, 8'he1,8'h24,8'h50,8'h34,
      8'hc3,8'h54,8'h67,8'hef, 8'h2e,8'hfd,8'h4d,8'h64,
      8'heb,8'hf8,8'h19,8'h68, 8'h34,8'h67,8'he2,8'hbf
    };

    v.msg_bytes = '{
      8'hdd,8'haf,8'h35,8'ha1, 8'h93,8'h61,8'h7a,8'hba,
      8'hcc,8'h41,8'h73,8'h49, 8'hae,8'h20,8'h41,8'h31,
      8'h12,8'he6,8'hfa,8'h4e, 8'h89,8'ha9,8'h7e,8'ha2,
      8'h0a,8'h9e,8'hee,8'he6, 8'h4b,8'h55,8'hd3,8'h9a,
      8'h21,8'h92,8'h99,8'h2a, 8'h27,8'h4f,8'hc1,8'ha8,
      8'h36,8'hba,8'h3c,8'h23, 8'ha3,8'hfe,8'heb,8'hbd,
      8'h45,8'h4d,8'h44,8'h23, 8'h64,8'h3c,8'he8,8'h0e,
      8'h2a,8'h9a,8'hc9,8'h4f, 8'ha5,8'h4c,8'ha4,8'h9f
    };

    return v;
  endfunction

  //-------------------------------------------------------------------
  // Negative vector: TEST 1 with one byte of S corrupted -> must fail
  //-------------------------------------------------------------------
  function automatic ed25519_vector_t get_test1_bad_sig();
    ed25519_vector_t v;
    v = get_test1();
    v.name        = "RFC8032_TEST1_CORRUPT_S";
    v.expect_pass = 1'b0;
    v.s_bytes[0]  = v.s_bytes[0] ^ 8'h01; // flip one bit -> invalid S
    return v;
  endfunction

endpackage : rfc8032_vectors_pkg
