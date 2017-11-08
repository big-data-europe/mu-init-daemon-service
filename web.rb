require 'json'

configure do
  set :step_status, { not_started: 'not_started', starting: 'starting', running: 'running', ready: 'ready', done: 'done', failed: 'failed' }
end

###
# Vocabularies
###

PWO = RDF::Vocabulary.new('http://purl.org/spar/pwo/')
PIP = RDF::Vocabulary.new('http://www.big-data-europe.eu/vocabularies/pipeline/')



###
# Process delta reports
###
post '/process_delta' do
  unless ENV["CHECK_HEALTH_STATUS"].nil? or ENV["CHECK_HEALTH_STATUS"].downcase == "false"
    log.debug "Processing delta"
    begin
      # for some reason, the @json_body is not working...
      request.body.rewind
      body = JSON.parse(request.body.read)

      process_delta(body['delta'][0]['inserts'])
      status 204
    rescue
      log.error "Exception occurred when trying to process delta"
      error("Exception occurred when trying to process delta")
      status 500
    end
  else
    log.debug "Ignoring process delta, as [CHECK_HEALTH_STATUS] is false"
  end
end

###
# Validate if a given step (specified by its code) of a pipeline can be started.
# The step is specified through the step query param.
# E.g. /canStart?step="hdfs_init"
###
get '/canStart' do
  content_type 'text/plain'

  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?
  error("No step found with code '#{params['step']}'") if not ask_if_step_code_exists(params['step'])

  previous_steps_are_done = !ask_if_previous_steps_are_not_done(params['step'])

  (previous_steps_are_done).to_s
end

###
# Starts the [optional] starting phase of a step in a pipeline.
# The step is specified through the step query param.
# E.g. /boot?step="hdfs_init"
###
put '/boot' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?

  result = select_step_by_code(params['step'])
  error("No step found with code '#{params['step']}'") if result.empty?
  step = result.first[:step].to_s

  update_step_status(step, settings.step_status[:starting])

  status 204
end

###
# Start the execution of a step in a pipeline.
# The step is specified through the step query param.
# E.g. /execute?step="hdfs_init"
###
put '/execute' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?

  result = select_step_by_code(params['step'])
  error("No step found with code '#{params['step']}'") if result.empty?
  step = result.first[:step].to_s

  update_step_status(step, settings.step_status[:running])

  status 204
end

###
# Sets the ready state of a step in a pipeline.
# The step is specified through the step query param.
# E.g. /ready?step="hdfs_init"
###
put '/ready' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?

  result = select_step_by_code(params['step'])
  error("No step found with code '#{params['step']}'") if result.empty?
  step = result.first[:step].to_s

  update_step_status(step, settings.step_status[:ready])

  status 204
end

###
# Finish the execution of a step in a pipeline.
# The step is specified through the step query param.
# E.g. /finish?step="hdfs_init"
###
put '/finish' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?

  result = select_step_by_code(params['step'])
  error("No step found with code '#{params['step']}'") if result.empty?
  step = result.first[:step].to_s

  update_step_status(step, settings.step_status[:done])

  status 204
end

###
# Indicates failure of the execution of a step in a pipeline.
# The step is specified through the step query param.
# E.g. /fail?step="hdfs_init"
###
put '/fail' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?

  result = select_step_by_code(params['step'])
  error("No step found with code '#{params['step']}'") if result.empty?
  step = result.first[:step].to_s

  update_step_status(step, settings.step_status[:failed])

  status 204
end


###
# Helpers
###

helpers do

  def process_delta(delta)
    log.debug "Start processing delta"
    delta.each do | triple |
      if triple["o"]["value"].to_s == "http://ontology.aksw.org/dockevent/actions/health_status"
        process_health_check_for_uri(triple["s"]["value"])
      end
    end
    log.debug "Finished processing delta"
  end

  def process_health_check_for_uri(uri)
    log.info "Processing health check for URI <#{uri}>"
    default_step_status_healthy = ENV["DEFAULT_STEP_STATUS_WHEN_HEALTHY"]
    default_step_status_unhealthy = ENV["DEFAULT_STEP_STATUS_WHEN_UNHEALTHY"]
    query = "WITH <#{settings.graph}>
    DELETE
    {
      ?step <#{PIP.status}> ?old_status .
    }
    INSERT
    {
      ?step <#{PIP.status}> ?new_status .
    }
    WHERE
    {
      # getting health check event info
      <#{uri}> a <http://ontology.aksw.org/dockevent/types/event> ;
      <http://ontology.aksw.org/dockevent/action> <http://ontology.aksw.org/dockevent/actions/health_status> ;
      <http://ontology.aksw.org/dockevent/source> ?source ;
      <http://ontology.aksw.org/dockevent/actionExtra> ?event_health_status .

      # getting container info
      ?container <http://ontology.aksw.org/dockevent/source> ?source .
      ?container <http://ontology.aksw.org/dockevent/container> ?start_event .

      # getting starting event info
      ?start_event <http://ontology.aksw.org/dockcontainer/env> ?container_env_step .
      FILTER(STRSTARTS(STR(?container_env_step), 'INIT_DAEMON_STEP='))
      BIND(STRAFTER(STR(?container_env_step), 'INIT_DAEMON_STEP=') AS ?step_code)

      # getting step
      ?step <#{PIP.code}> ?step_code ;
        a <#{PWO.Step}> ;
      <#{PIP.status}> ?old_status .

      # getting status to apply if healthy
      OPTIONAL{
        ?start_event <http://ontology.aksw.org/dockcontainer/env> ?container_env_status_healthy .
        FILTER(STRSTARTS(STR(?container_env_status_healthy), 'INIT_DAEMON_STEP_STATUS_WHEN_HEALTHY='))
        BIND(STRAFTER(STR(?container_env_status_healthy), 'INIT_DAEMON_STEP_STATUS_WHEN_HEALTHY=') AS ?container_step_status_healthy)
      }
      BIND(IF(BOUND(?container_step_status_healthy), STR(?container_step_status_healthy), '#{default_step_status_healthy}') AS ?healthy_status)

      # getting status to apply if unhealthy
      OPTIONAL{
        ?start_event <http://ontology.aksw.org/dockcontainer/env> ?container_env_status_unhealthy .
        FILTER(STRSTARTS(STR(?container_env_status_unhealthy), 'INIT_DAEMON_STEP_STATUS_WHEN_UNHEALTHY='))
        BIND(STRAFTER(STR(?container_env_status_unhealthy), 'INIT_DAEMON_STEP_STATUS_WHEN_UNHEALTHY=') AS ?container_step_status_unhealthy)
      }
      BIND(IF(BOUND(?container_step_status_unhealthy), STR(?container_step_status_unhealthy), '#{default_step_status_unhealthy}') AS ?unhealthy_status)

      BIND(IF(?event_health_status = 'healthy', ?healthy_status, ?unhealthy_status) AS ?new_status)

      # no sense updating if it's already the same
      FILTER(?old_status != ?new_status)
    }"

    log.debug "Executing query:\n#{query}"
    update(query)
  end

  def ask_if_step_code_exists(step_code)
    query = " ASK FROM <#{settings.graph}> WHERE {"
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{PIP.code}> '#{step_code.downcase}' . "
    query += " }"
    query(query)
  end

  def select_step_by_code(step_code)
    query = " SELECT ?step FROM <#{settings.graph}> WHERE {"
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{PIP.code}> '#{step_code.downcase}' . "
    query += " }"
    query(query)
  end

  def ask_if_previous_steps_are_not_done(step_code)
    query = " ASK FROM <#{settings.graph}> WHERE {"
    query += "  ?pipeline a <#{PWO.Workflow}> ; "
    query += "    <#{PWO.hasStep}> ?step, ?prev_step . "
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{PIP.code}> '#{step_code.downcase}' ; "
    query += "    <#{PIP.order}> ?sequence . "
    query += "  ?prev_step a <#{PWO.Step}> ; "
    query += "    <#{PIP.order}> ?prev_sequence ; "
    query += "    <#{PIP.status}> ?prev_status . "
    query += "  FILTER(?prev_sequence < ?sequence) "
    query += "  FILTER(?prev_status != '#{settings.step_status[:done]}' && ?prev_status != '#{settings.step_status[:ready]}') "
    query += " }"
    query(query)
  end

  def delete_step_status(step)
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{step}> <#{PIP.status}> ?status ."
    query += " }"
    query += " WHERE {"
    query += "   <#{step}> <#{PIP.status}> ?status ."
    query += " }"
    update(query)
  end

  def insert_step_status(step, status)
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{step}> <#{PIP.status}> '#{status}' ."
    query += "   }"
    query += " }"
    update(query)
  end

  def update_step_status(step, status)
    delete_step_status(step)
    insert_step_status(step, status)
  end

end
