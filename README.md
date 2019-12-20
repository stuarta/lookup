This is a simple helper app designed only to be run
on the local machine, to lookup users out of SSO, in
order to facilitate a migration of trac away to another
bug tracker.

Setup:
* Setup a confidential client in keycloak, and enable service account
* Copy JSON format data from installation tab to a file `client-credentials.json`
* Usual bundle install
* Rackup! up up and away
