configure do
  set :step_status, { not_started: 'not_started', starting: 'starting', running: 'running', ready: 'ready', done: 'done', failed: 'failed' }
end

###
# Vocabularies
###

PWO = RDF::Vocabulary.new('http://purl.org/spar/pwo/')
PIP = RDF::Vocabulary.new('http://www.big-data-europe.eu/vocabularies/pipeline/')
DC = RDF::Vocabulary.new('http://ontology.aksw.org/dockcontainer/')
DE = RDF::Vocabulary.new('http://ontology.aksw.org/dockevent/')
DEA = RDF::Vocabulary.new('http://ontology.aksw.org/dockevent/actions/')
DEAHS = RDF::Vocabulary.new('http://ontology.aksw.org/dockevent/actions/health_status')
DET = RDF::Vocabulary.new('http://ontology.aksw.org/dockevent/types/')
###
# Validate if a given step (specified by its code) of a pipeline can be started.
# The step is specified through the step query param.
# E.g. /canStart?step="hdfs_init"
###
get '/canStart' do
  content_type 'text/plain'

  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?
  error("No step found with code '#{params['step']}'") if not ask_if_step_code_exists(params['step'])

  # Checks if we should try to discover the status of a step from the health check of a container
  unless ENV["CHECK_HEALTH_STATUS"].nil? or ENV["CHECK_HEALTH_STATUS"].downcase == "false"
    check_and_update_steps_through_health_status(params['step'])
  end
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

  # TODO : check why DEA.health_status doesn't work => had to create a new entry in the dictionary
  # TODO : step status should be provided probably by ENV variable
  def check_and_update_steps_through_health_status(step_code)
    step_status = settings.step_status[:ready]
    health_status = ENV["HEALTH_STATUS_VALUE"]
    check_only_latest_healthcheck = ENV["CHECK_ONLY_LATEST_HEALTHCHECK"].downcase != "false"

    query = "WITH <#{settings.graph}> "
    query += " DELETE {?prev_step <#{PIP.status}> ?prev_status .} "
    query += " INSERT {?prev_step <#{PIP.status}> '#{step_status}' .} "
    query += " WHERE { "
    query += " 	?pipeline a <#{PWO.Workflow}> ;  "
    query += " 		<#{PWO.hasStep}> ?current_step, ?prev_step .  "
    query += " 	?current_step a <#{PWO.Step}> ;  "
    query += " 		<#{PIP.code}> '#{step_code.downcase}' ; "
    query += " 		<#{PIP.order}> ?sequence . "
    query += " 	?prev_step a <#{PWO.Step}> ;  "
    query += " 		<#{PIP.code}> ?step_code ; "
    query += " 		<#{PIP.order}> ?prev_sequence ; "
    query += " 		<#{PIP.status}> ?prev_status . "
    query += " 	FILTER(?prev_sequence < ?sequence) "
    # there's no point in going further if the step is already in the correct state
    query += " 	FILTER(?prev_status != '#{step_status}') "

    query += " 	?start_event <#{DC.env}> ?label . "
    query += " 	BIND(STRAFTER(STR(?label), 'INIT_DAEMON_STEP=') AS ?container_step_code) "
    query += " 	FILTER(STR(?step_code) = STR(?container_step_code)) "
    query += " 	?container_event <#{DE.container}> ?start_event . "
    query += " 	?container_event <#{DE.source}> ?source . "
    query += " 	{ "
    query += " 		SELECT ?status ?timestamp "
    query += " 		WHERE "
    query += " 		{ "
    query += " 			?health_event <#{DE.source}> ?source ; "
    query += " 			 a <#{DET.event}> ; "
    query += " 			 <#{DE.action}> <#{DEAHS}> ; "
    query += " 			 <#{DE.actionExtra}> ?status ; "
    query += " 			 <#{DE.timeNano}> ?timestamp . "
    query += " 		} "
    query += " 		ORDER BY DESC(?timestamp) "
    if check_only_latest_healthcheck
      query += " 		LIMIT 1 "
    end
    query += " 	} "
    query += " 	FILTER(?status = '#{health_status}') "
    query += " } "

    update(query)
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
