when HTTP_REQUEST {
  # Check if it's a token request
  if { [HTTP::uri] contains "/v1/token" and [HTTP::method] equals "POST" } {
    set client_id ""
    set client_secret ""

    # Collect the length of the HTTP request body specified in the Content-Length header
    set contentLength [HTTP::header "Content-Length"]

    # Check if the Authorization header is present and is Basic
    if { [HTTP::header exists "Authorization"] and [string tolower [lindex [HTTP::header "Authorization"] 0]] equals "basic" } {

      # Get the client ID and secret from the Authorization header
      set client_id [HTTP::username]
      set client_secret [HTTP::password]

      log local0. "Client ID from Authorization header: $client_id"

      # Remove the Authorization header
      HTTP::header remove "Authorization"

      # convert basic auth to client creds in body
      HTTP::payload replace 0 [HTTP::payload length] "[HTTP::payload]&client_id=$client_id&client_secret=$client_secret"
    }

    HTTP::collect $contentLength
  }
}

when HTTP_REQUEST_DATA {
  set payload [HTTP::payload]

  if { [HTTP::payload] contains "grant_type=client_credentials" } {
    # convert client credentials to ROPC
    regsub "grant_type=client_credentials" $payload "grant_type=password\\&username=user\\&password=password" payload

    # Parse the payload into key-value pairs
    foreach pair [split $payload "&"] {
      set name_value [split $pair "="]
      set name [URI::decode [lindex $name_value 0]]
      set value [URI::decode [lindex $name_value 1]]

      # extract client_id and client_secret
      if { $name eq "client_id" } {
        set client_id $value
      } elseif { $name eq "client_secret" } {
        set client_secret $value
      }
    }

    # convert Okta client IDs to F5-compatible form
    # F5 client IDs are 48 hex digits
    if { $client_id ne "" && [string length $client_id] < 48} {
      binary scan [CRYPTO::hash -alg sha256 $client_id] H* client_id_hash
      set client_id_trimmed [string range $client_id_hash 0 47]

      log local0. "client_id: $client_id"
      log local0. "SHA-256(client_id): $client_id_hash"
      log local0. "Trimmed (24 bytes): $client_id_trimmed"

      # generate full SHA-256 hash of client_secret
      if { $client_secret ne "" } {
        binary scan [CRYPTO::hash -alg sha256 $client_secret] H* client_secret_hash

        log local0. "client_secret: $client_secret"
        log local0. "SHA-256(client_secret): $client_secret_hash"
      } else {
        log local0. "client_secret not found in payload."
      }

      regsub "client_id=$client_id" $payload "client_id=$client_id_trimmed" payload
      regsub "client_secret=$client_secret" $payload "client_secret=$client_secret_hash" payload
    } else {
      log local0. "client_id is F5-formatted or not found in payload"
    }

    #ACCESS::session create -flow
    #ACCESS::session data set session.custom.original_client_id $client_id

    HTTP::payload replace 0 [HTTP::header Content-Length] $payload
    log local0. "HTTP payload for APM: [HTTP::payload]"

    HTTP::release
  }
}

when ACCESS_POLICY_AGENT_EVENT {
  if { [ACCESS::policy agent_id] eq "process_client_app_data" } {
    ACCESS::session data set "session.custom.original_client_id" $client_id

  }
}
