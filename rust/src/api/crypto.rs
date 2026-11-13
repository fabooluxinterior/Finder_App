use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use base64::engine::general_purpose::STANDARD_NO_PAD as B64;
use sha2::{Digest, Sha256};
use vodozemac::olm::{Account, AccountPickle, OlmMessage, Session, SessionConfig, SessionPickle};
use vodozemac::{Curve25519PublicKey, Ed25519PublicKey, Ed25519Signature};
use zeroize::Zeroizing;

/// Olm v1 is the configuration audited and deployed by Matrix clients.
fn session_config() -> SessionConfig {
    SessionConfig::version_1()
}

fn pickle_key(key: &[u8]) -> Result<Zeroizing<[u8; 32]>> {
    let arr: [u8; 32] = key.try_into().map_err(|_| anyhow!("pickle key must be 32 bytes"))?;
    Ok(Zeroizing::new(arr))
}

fn load_account(pickle: &str, key: &[u8]) -> Result<Account> {
    let p = AccountPickle::from_encrypted(pickle, &*pickle_key(key)?).context("account pickle")?;
    Ok(Account::from_pickle(p))
}

fn save_account(acc: &Account, key: &[u8]) -> Result<String> {
    Ok(acc.pickle().encrypt(&*pickle_key(key)?))
}

fn load_session(pickle: &str, key: &[u8]) -> Result<Session> {
    let p = SessionPickle::from_encrypted(pickle, &*pickle_key(key)?).context("session pickle")?;
    Ok(Session::from_pickle(p))
}

fn save_session(s: &Session, key: &[u8]) -> Result<String> {
    Ok(s.pickle().encrypt(&*pickle_key(key)?))
}

fn curve(b64: &str) -> Result<Curve25519PublicKey> {
    Curve25519PublicKey::from_base64(b64).context("curve25519 key")
}

fn otk_signing_payload(identity_curve25519: &str, otk: &str) -> String {
    format!("finder:otk:v1:{identity_curve25519}:{otk}")
}

// ----------------------------------------------------------------- types ---

pub struct DeviceIdentity {
    /// Encrypted account pickle (persist this, encrypted, on the device).
    pub account_pickle: String,
    /// Curve25519 identity key (base64). Also used as the device id.
    pub curve25519: String,
    /// Ed25519 signing key (base64).
    pub ed25519: String,
}

pub struct SignedOneTimeKey {
    pub key_id: String,
    pub public_key: String,
    pub signature: String,
}

pub struct OneTimeKeyBatch {
    pub account_pickle: String,
    pub keys: Vec<SignedOneTimeKey>,
    /// Signed fallback key, used when the server runs out of one-time keys.
    pub fallback: Option<SignedOneTimeKey>,
}

pub struct EncryptedMessage {
    pub session_pickle: String,
    pub session_id: String,
    /// 0 = pre-key message (first in a session), 1 = normal message.
    pub message_type: u32,
    pub ciphertext: String,
}

pub struct DecryptedMessage {
    /// Updated account pickle when a new inbound session was created
    /// (the consumed one-time key is removed from it); otherwise None.
    pub account_pickle: Option<String>,
    pub session_pickle: String,
    pub session_id: String,
    pub plaintext: Vec<u8>,
}

pub struct EncryptedBlob {
    /// Random per-file AES-256 key (send it inside the E2EE message).
    pub key: Vec<u8>,
    pub nonce: Vec<u8>,
    pub ciphertext: Vec<u8>,
    /// SHA-256 of the ciphertext, checked before decryption.
    pub sha256: Vec<u8>,
}

// --------------------------------------------------------------- account ---

/// Creates a new device identity (Curve25519 + Ed25519 keypairs).
pub fn create_device(pickle_key: Vec<u8>) -> Result<DeviceIdentity> {
    let acc = Account::new();
    let ids = acc.identity_keys();
    Ok(DeviceIdentity {
        account_pickle: save_account(&acc, &pickle_key)?,
        curve25519: ids.curve25519.to_base64(),
        ed25519: ids.ed25519.to_base64(),
    })
}

pub fn device_identity(account_pickle: String, pickle_key: Vec<u8>) -> Result<DeviceIdentity> {
    let acc = load_account(&account_pickle, &pickle_key)?;
    let ids = acc.identity_keys();
    Ok(DeviceIdentity {
        account_pickle,
        curve25519: ids.curve25519.to_base64(),
        ed25519: ids.ed25519.to_base64(),
    })
}

/// Generates `count` signed one-time keys (and a fallback key if none is
/// pending) and marks them published.
pub fn generate_one_time_keys(
    account_pickle: String,
    pickle_key: Vec<u8>,
    count: u32,
) -> Result<OneTimeKeyBatch> {
    let mut acc = load_account(&account_pickle, &pickle_key)?;
    let identity = acc.curve25519_key().to_base64();
    acc.generate_one_time_keys(count.min(acc.max_number_of_one_time_keys() as u32) as usize);
    if acc.fallback_key().is_empty() {
        acc.generate_fallback_key();
    }
    let sign = |acc: &Account, id: String, k: Curve25519PublicKey| {
        let pk = k.to_base64();
        SignedOneTimeKey {
            signature: acc.sign(otk_signing_payload(&identity, &pk)).to_base64(),
            key_id: id,
            public_key: pk,
        }
    };
    let keys = acc
        .one_time_keys()
        .into_iter()
        .map(|(id, k)| sign(&acc, id.to_base64(), k))
        .collect();
    let fallback = acc.fallback_key().into_iter().next().map(|(id, k)| sign(&acc, id.to_base64(), k));
    acc.mark_keys_as_published();
    Ok(OneTimeKeyBatch { account_pickle: save_account(&acc, &pickle_key)?, keys, fallback })
}

pub fn sign(account_pickle: String, pickle_key: Vec<u8>, message: Vec<u8>) -> Result<String> {
    Ok(load_account(&account_pickle, &pickle_key)?.sign(message).to_base64())
}

pub fn verify_signature(ed25519: String, message: Vec<u8>, signature: String) -> bool {
    let (Ok(key), Ok(sig)) = (Ed25519PublicKey::from_base64(&ed25519), Ed25519Signature::from_base64(&signature))
    else {
        return false;
    };
    key.verify(&message, &sig).is_ok()
}

/// Verifies a claimed one-time key was signed by the owning device.
pub fn verify_one_time_key(device_ed25519: String, device_curve25519: String, otk: String, signature: String) -> bool {
    verify_signature(device_ed25519, otk_signing_payload(&device_curve25519, &otk).into_bytes(), signature)
}

/// 60-digit safety number for out-of-band verification, identical on both
/// sides (inputs are sorted).
pub fn safety_number(my_ed25519_keys: Vec<String>, their_ed25519_keys: Vec<String>) -> String {
    let fp = |mut keys: Vec<String>| {
        keys.sort();
        let mut h = Sha256::new();
        h.update(b"finder:safety:v1");
        for k in keys {
            h.update(k.as_bytes());
        }
        let d = h.finalize();
        (0..6)
            .map(|i| {
                let n = u64::from_be_bytes([0, 0, 0, d[i * 5], d[i * 5 + 1], d[i * 5 + 2], d[i * 5 + 3], d[i * 5 + 4]]);
                format!("{:05}", n % 100_000)
            })
            .collect::<String>()
    };
    let (a, b) = (fp(my_ed25519_keys), fp(their_ed25519_keys));
    if a <= b { format!("{a}{b}") } else { format!("{b}{a}") }
}

// --------------------------------------------------------------- session ---

pub fn create_outbound_session(
    account_pickle: String,
    pickle_key: Vec<u8>,
    their_curve25519: String,
    their_one_time_key: String,
) -> Result<String> {
    let acc = load_account(&account_pickle, &pickle_key)?;
    let s = acc.create_outbound_session(session_config(), curve(&their_curve25519)?, curve(&their_one_time_key)?)?;
    save_session(&s, &pickle_key)
}

pub fn encrypt(session_pickle: String, pickle_key: Vec<u8>, plaintext: Vec<u8>) -> Result<EncryptedMessage> {
    let mut s = load_session(&session_pickle, &pickle_key)?;
    let msg = s.encrypt(&plaintext)?;
    let (t, bytes) = msg.to_parts();
    Ok(EncryptedMessage {
        session_id: s.session_id(),
        session_pickle: save_session(&s, &pickle_key)?,
        message_type: t as u32,
        ciphertext: B64.encode(bytes),
    })
}

fn parse(message_type: u32, ciphertext: &str) -> Result<OlmMessage> {
    let bytes = B64.decode(ciphertext).context("ciphertext base64")?;
    Ok(OlmMessage::from_parts(message_type as usize, &bytes)?)
}

/// Does this pre-key message belong to an existing session?
pub fn session_matches(session_pickle: String, pickle_key: Vec<u8>, message_type: u32, ciphertext: String) -> Result<bool> {
    let s = load_session(&session_pickle, &pickle_key)?;
    match parse(message_type, &ciphertext)? {
        OlmMessage::PreKey(m) => Ok(s.session_keys() == m.session_keys()),
        OlmMessage::Normal(_) => Ok(false),
    }
}

/// Decrypts with an existing session. Replayed or tampered messages fail
/// MAC verification / message-key lookup and return an error.
pub fn decrypt(session_pickle: String, pickle_key: Vec<u8>, message_type: u32, ciphertext: String) -> Result<DecryptedMessage> {
    let mut s = load_session(&session_pickle, &pickle_key)?;
    let plaintext = s.decrypt(&parse(message_type, &ciphertext)?)?;
    Ok(DecryptedMessage {
        account_pickle: None,
        session_id: s.session_id(),
        session_pickle: save_session(&s, &pickle_key)?,
        plaintext,
    })
}

/// Creates a session from an incoming pre-key message and decrypts it.
/// The consumed one-time key is removed, so the same pre-key message
/// cannot be replayed into a second session.
pub fn decrypt_inbound(
    account_pickle: String,
    pickle_key: Vec<u8>,
    their_curve25519: String,
    message_type: u32,
    ciphertext: String,
) -> Result<DecryptedMessage> {
    let OlmMessage::PreKey(m) = parse(message_type, &ciphertext)? else {
        bail!("not a pre-key message");
    };
    let mut acc = load_account(&account_pickle, &pickle_key)?;
    let r = acc.create_inbound_session(session_config(), curve(&their_curve25519)?, &m)?;
    Ok(DecryptedMessage {
        account_pickle: Some(save_account(&acc, &pickle_key)?),
        session_id: r.session.session_id(),
        session_pickle: save_session(&r.session, &pickle_key)?,
        plaintext: r.plaintext,
    })
}

// ----------------------------------------------------------- attachments ---

fn random<const N: usize>() -> Result<[u8; N]> {
    let mut b = [0u8; N];
    getrandom::fill(&mut b).map_err(|e| anyhow!("rng: {e}"))?;
    Ok(b)
}

/// AES-256-GCM with a fresh random key and nonce per blob. `aad` binds the
/// ciphertext to its context (e.g. "voice:<message id>").
pub fn encrypt_blob(plaintext: Vec<u8>, aad: Vec<u8>) -> Result<EncryptedBlob> {
    let key = Zeroizing::new(random::<32>()?);
    let nonce = random::<12>()?;
    let cipher = Aes256Gcm::new_from_slice(&key[..]).map_err(|_| anyhow!("key"))?;
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), Payload { msg: &plaintext, aad: &aad })
        .map_err(|_| anyhow!("encryption failed"))?;
    let sha256 = Sha256::digest(&ciphertext).to_vec();
    Ok(EncryptedBlob { key: key.to_vec(), nonce: nonce.to_vec(), ciphertext, sha256 })
}

pub fn decrypt_blob(key: Vec<u8>, nonce: Vec<u8>, ciphertext: Vec<u8>, sha256: Vec<u8>, aad: Vec<u8>) -> Result<Vec<u8>> {
    if Sha256::digest(&ciphertext).as_slice() != sha256.as_slice() {
        bail!("attachment hash mismatch");
    }
    if nonce.len() != 12 {
        bail!("bad nonce");
    }
    let key = Zeroizing::new(key);
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|_| anyhow!("key"))?;
    cipher
        .decrypt(Nonce::from_slice(&nonce), Payload { msg: &ciphertext, aad: &aad })
        .map_err(|_| anyhow!("attachment authentication failed"))
}

/// 32 random bytes, e.g. for a new local pickle key.
pub fn random_key() -> Result<Vec<u8>> {
    Ok(random::<32>()?.to_vec())
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
