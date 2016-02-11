configure do
  set :step_status, { not_started: 'not_started', running: 'running', done: 'done' }
end

###
# Vocabularies
###

PWO = RDF::Vocabulary.new('http://purl.org/spar/pwo/')
POC = RDF::Vocabulary.new('http://www.big-data-europe.eu/vocabularies/poc/')



###
# Validate if a given step (specified by its code) of a pipeline can be started. The step is specified through the step query param. E.g. '/canStart?step="hdfs_initialized".
###
get '/canStart' do
  error('Step query parameter is required') if params['step'].nil? or params['step'].empty?
  error("No step found with code '#{params['step']}'") if not ask_if_step_code_exists(params['step'])
  
  previous_steps_are_done = !ask_if_previous_steps_are_not_done(params['step'])

  (previous_steps_are_done).to_s
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
  
end

