//! Finder end-to-end encryption core.
//!
//! A thin, stateless wrapper over `vodozemac` (Matrix's audited Rust Olm /
//! Double Ratchet implementation, Apache-2.0) plus AES-256-GCM for
//! attachments. Every call takes encrypted pickles in and returns updated
//! encrypted pickles, so private key material only exists inside Rust for
//! the duration of a call and is never handed to Dart in the clear.
//!
//! No cryptographic primitive or protocol is implemented here; this crate
//! only composes reviewed building blocks.

pub mod api;
mod frb_generated;
