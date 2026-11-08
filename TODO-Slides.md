# Slide changes to make

## Day 1 setup

- [ ] Add a concise setup slide (or update the existing environment setup slide) showing the required student sequence: clone the complete lab repository, copy `.env.example` to `.env`, enter account/user/password, install `SetUp/requirements.txt`, run `SetUp/test_connection.py`, then run `SetUp/key_pair_setup.py`.
- [ ] Explain the purpose of key-pair authentication: the script generates a private/public key pair, registers the public key on the Snowflake user using an `ACCOUNTADMIN` password connection, then verifies a new connection using the private key and classroom role.
- [ ] Show the expected success checks and where the private key is stored; emphasize that the private key must not be committed or shared. Do not put real credentials or key material on slides.
- [ ] State that Windows is the supported local setup for class; students on other operating systems should ask for instructor assistance.

Recommendation: teach this as a short setup workflow slide, not a general cryptography lesson. Add a second slide only if the existing deck needs a simple public-key/private-key diagram to explain why the public key is registered while the private key stays on the student's machine.

The slide deck is not present in this repository, so this is a change log item for the deck update rather than a slide edit.
