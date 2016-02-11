configure do
  set :step_status, { not_started: 'not_started', running: 'running', done: 'done' }
end

###
# Vocabularies
###

PWO = RDF::Vocabulary.new('http://purl.org/spar/pwo/')
POC = RDF::Vocabulary.new('http://www.big-data-europe.eu/vocabularies/poc/')



###
# Validate if a given step (specified by its code) of a pipeline can be started.
# The step is specified through the step query param.
# E.g. /canStart?step="hdfs_init"
###
get '/canStart' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?
  error("No step found with code '#{params['step']}'") if not ask_if_step_code_exists(params['step'])
  
  previous_steps_are_done = !ask_if_previous_steps_are_not_done(params['step'])

  (previous_steps_are_done).to_s
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
# Helpers
###

helpers do

  def ask_if_step_code_exists(step_code)
    query = " ASK FROM <#{settings.graph}> WHERE {"
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{POC.code}> '#{step_code.downcase}' . "
    query += " }"
    query(query)    
  end

  def select_step_by_code(step_code)
    query = " SELECT ?step FROM <#{settings.graph}> WHERE {"
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{POC.code}> '#{step_code.downcase}' . "
    query += " }"
    query(query)    
  end

  def ask_if_previous_steps_are_not_done(step_code)
    query = " ASK FROM <#{settings.graph}> WHERE {"
    query += "  ?pipeline a <#{PWO.Workflow}> ; "
    query += "    <#{PWO.hasStep}> ?step, ?prev_step . "
    query += "  ?step a <#{PWO.Step}> ; "
    query += "    <#{POC.code}> '#{step_code.downcase}' ; "
    query += "    <#{POC.order}> ?sequence . "
    query += "  ?prev_step a <#{PWO.Step}> ; "
    query += "    <#{POC.order}> ?prev_sequence ; "
    query += "    <#{POC.status}> ?prev_status . "
    query += "  FILTER(?prev_sequence < ?sequence) "
    query += "  FILTER(?prev_status != '#{settings.step_status[:done]}') "
    query += " }"
    query(query)
  end

  def delete_step_status(step)
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   <#{step}> <#{POC.status}> ?status ."
    query += " }"
    query += " WHERE {"
    query += "   <#{step}> <#{POC.status}> ?status ."
    query += " }"
    update(query)
  end

  def insert_step_status(step, status)
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{step}> <#{POC.status}> '#{status}' ."
    query += "   }"
    query += " }"
    update(query)
  end

  def update_step_status(step, status)
    delete_step_status(step)
    insert_step_status(step, status)
  end
  
end

