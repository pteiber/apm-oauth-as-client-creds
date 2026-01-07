when ACCESS_POLICY_AGENT_EVENT {
  if { [ACCESS::policy agent_id] eq "process_client_app_data" } {
    # Get client_id from session (adjust the session var name as needed)
    set client_id [ACCESS::session data get "session.oauth.authz.client_id"]
    if { $client_id ne "" } {
      # Lookup in the data group
      set kv_string [class match -value $client_id equals oauth-client-app-data]
      if { $kv_string ne "" } {
        log local0. "processing client app data $kv_string"
        # Split into individual key=value pairs
        foreach pair [split $kv_string "|"] {
          if { [string match "*=*" $pair] } {
            set kv [split $pair "="]
            set key [lindex $kv 0]
            set val [lindex $kv 1]
            #log local0. "setting $key=$val"
            # Write into APM session variable namespace
            ACCESS::session data set "session.custom.$key" $val
          }
        }
      } else {
        log local0. "No client app data found for client_id=$client_id"
      }
    } else {
      log local0. "No client_id in session"
    }
  }
}
