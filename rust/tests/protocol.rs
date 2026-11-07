use finder_crypto::api::crypto::*;

fn device() -> (DeviceIdentity, Vec<u8>) {
    let k = random_key().unwrap();
    (create_device(k.clone()).unwrap(), k)
}

#[test]
fn full_exchange_replay_and_tamper() {
    let (alice, ak) = device();
    let (bob, bk) = device();

    let batch = generate_one_time_keys(bob.account_pickle.clone(), bk.clone(), 5).unwrap();
    let bob_pickle = batch.account_pickle;
    let otk = &batch.keys[0];
    assert!(verify_one_time_key(bob.ed25519.clone(), bob.curve25519.clone(), otk.public_key.clone(), otk.signature.clone()));
    // A forged/swapped OTK must fail signature verification.
    assert!(!verify_one_time_key(alice.ed25519.clone(), bob.curve25519.clone(), otk.public_key.clone(), otk.signature.clone()));

    let a_sess = create_outbound_session(alice.account_pickle.clone(), ak.clone(), bob.curve25519.clone(), otk.public_key.clone()).unwrap();
    let m1 = encrypt(a_sess, ak.clone(), b"hello bob".to_vec()).unwrap();
    assert_eq!(m1.message_type, 0);
    assert!(!m1.ciphertext.contains("hello"));

    let d1 = decrypt_inbound(bob_pickle.clone(), bk.clone(), alice.curve25519.clone(), m1.message_type, m1.ciphertext.clone()).unwrap();
    assert_eq!(d1.plaintext, b"hello bob");
    let bob_pickle2 = d1.account_pickle.unwrap();

    // Replaying the pre-key message against the updated account fails: the OTK was consumed.
    assert!(decrypt_inbound(bob_pickle2.clone(), bk.clone(), alice.curve25519.clone(), m1.message_type, m1.ciphertext.clone()).is_err());

    // Bob replies; Alice decrypts with her session (ratchet advances).
    let r1 = encrypt(d1.session_pickle, bk.clone(), b"hi alice".to_vec()).unwrap();
    assert_eq!(r1.message_type, 1);
    let ad = decrypt(m1.session_pickle, ak.clone(), r1.message_type, r1.ciphertext.clone()).unwrap();
    assert_eq!(ad.plaintext, b"hi alice");

    // Replay of a normal message fails (message key already used).
    assert!(decrypt(ad.session_pickle.clone(), ak.clone(), r1.message_type, r1.ciphertext.clone()).is_err());

    // Tampered ciphertext fails MAC verification.
    let r2 = encrypt(r1.session_pickle, bk.clone(), b"second".to_vec()).unwrap();
    let mut raw = base64::Engine::decode(&base64::engine::general_purpose::STANDARD_NO_PAD, &r2.ciphertext).unwrap();
    let n = raw.len();
    raw[n / 2] ^= 0x01;
    let tampered = base64::Engine::encode(&base64::engine::general_purpose::STANDARD_NO_PAD, &raw);
    assert!(decrypt(ad.session_pickle.clone(), ak.clone(), r2.message_type, tampered).is_err());
    assert_eq!(decrypt(ad.session_pickle, ak.clone(), r2.message_type, r2.ciphertext).unwrap().plaintext, b"second");

    // Wrong pickle key cannot open state.
    assert!(device_identity(bob_pickle2, ak).is_err());
}

#[test]
fn blob_roundtrip_and_tamper() {
    let b = encrypt_blob(b"voice bytes".to_vec(), b"voice:1".to_vec()).unwrap();
    assert_eq!(b.key.len(), 32);
    assert_eq!(decrypt_blob(b.key.clone(), b.nonce.clone(), b.ciphertext.clone(), b.sha256.clone(), b"voice:1".to_vec()).unwrap(), b"voice bytes");
    assert!(decrypt_blob(b.key.clone(), b.nonce.clone(), b.ciphertext.clone(), b.sha256.clone(), b"voice:2".to_vec()).is_err());
    let mut c = b.ciphertext.clone();
    c[0] ^= 1;
    assert!(decrypt_blob(b.key, b.nonce, c, b.sha256, b"voice:1".to_vec()).is_err());
}

#[test]
fn safety_number_is_symmetric() {
    let a = vec!["A1".to_string(), "A2".to_string()];
    let b = vec!["B1".to_string()];
    let x = safety_number(a.clone(), b.clone());
    assert_eq!(x, safety_number(b, a));
    assert_eq!(x.len(), 60);
}
