configure do
  set :step_status, { not_started: 'not_started', starting: 'starting', running: 'running', ready: 'ready', done: 'done', failed: 'failed' }
end

###
# Vocabularies
###

PWO = RDF::Vocabulary.new('http://purl.org/spar/pwo/')
PIP = RDF::Vocabulary.new('http://www.big-data-europe.eu/vocabularies/pipeline/')



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
    query += "  FILTER(?prev_status != '#{settings.step_status[:done]}' && ?prev_status != '#{settings.step_status[:ready]}) "
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
