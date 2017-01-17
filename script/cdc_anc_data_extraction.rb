
Source_db = YAML.load(File.open(File.join(RAILS_ROOT, "config/database.yml"), "r"))['development']["database"]
CDCDataExtraction = 1

def start
  facility_name = GlobalProperty.find_by_sql("select property_value from global_property where property = 'current_health_center_name'").map(&:property_value).first

  start_date = "2016-01-01".to_date
  end_date = "2016-12-31".to_date
  puts "CDC ANC data extraction............................................................................................"

  puts "HIV status Known results (Newly)........................................................................."
  newly_registered_pmtct_known_results = newly_registered_pmtct_known_results(start_date, end_date)
  newly_registered_pmtct_known_results_less_than_15 = newly_registered_pmtct_known_results(start_date, end_date, 0, 14)
  newly_registered_pmtct_known_results_between_15_19 = newly_registered_pmtct_known_results(start_date, end_date, 15, 19)
  newly_registered_pmtct_known_results_between_20_24 = newly_registered_pmtct_known_results(start_date, end_date, 20, 24)
  newly_registered_pmtct_known_results_between_25_49 = newly_registered_pmtct_known_results(start_date, end_date, 25, 49)
  newly_registered_pmtct_known_results_more_than_50 = newly_registered_pmtct_known_results(start_date, end_date, 50, nil)

  puts "HIV status Known results (Cumulative)........................................................................."
  total_pmtct_known_results = pmtct_known_results(start_date, end_date)
  pmtct_known_results_less_than_15 = pmtct_known_results(start_date, end_date, 0, 14)
  pmtct_known_results_between_15_19 = pmtct_known_results(start_date, end_date, 15, 19)
  pmtct_known_results_between_20_24 = pmtct_known_results(start_date, end_date, 20, 24)
  pmtct_known_results_between_25_49 = pmtct_known_results(start_date, end_date, 25, 49)
  pmtct_known_results_more_than_50 = pmtct_known_results(start_date, end_date, 50, nil)

  puts "HIV status Known at entry results........................................................................."
  total_hiv_status_known_at_entry_positive = hiv_status_known_at_entry_positive(start_date, end_date)
  hiv_status_known_at_entry_positive_less_than_15 = hiv_status_known_at_entry_positive(start_date, end_date, 0, 14)
  hiv_status_known_at_entry_positive_between_15_19 = hiv_status_known_at_entry_positive(start_date, end_date, 15, 19)
  hiv_status_known_at_entry_positive_between_20_24 = hiv_status_known_at_entry_positive(start_date, end_date, 20, 24)
  hiv_status_known_at_entry_positive_between_25_49 = hiv_status_known_at_entry_positive(start_date, end_date, 25, 49)
  hiv_status_known_at_entry_positive_more_than_50 = hiv_status_known_at_entry_positive(start_date, end_date, 50, nil)

  if CDCDataExtraction == 1
    $resultsOutput = File.open("./CDCDataExtraction_ANC" + "#{facility_name}" + ".txt", "w")
    $resultsOutput  << "HIV status Known results (Newly registered)..........................................................\n"
    $resultsOutput  << " newly_registered_pmtct_known_results: #{newly_registered_pmtct_known_results}\n newly_registered_pmtct_known_results_less_than_15: #{newly_registered_pmtct_known_results_less_than_15}\n newly_registered_pmtct_known_results_between_15_19: #{newly_registered_pmtct_known_results_between_15_19}\n newly_registered_pmtct_known_results_between_20_24: #{newly_registered_pmtct_known_results_between_20_24}\n newly_registered_pmtct_known_results_between_25_49: #{newly_registered_pmtct_known_results_between_25_49}\n newly_registered_pmtct_known_results_more_than_50: #{newly_registered_pmtct_known_results_more_than_50}\n\n"
    $resultsOutput  << "HIV status Known results (Cumulative)..........................................................\n"
    $resultsOutput  << " total_pmtct_known_results: #{total_pmtct_known_results}\n pmtct_known_results_less_than_15: #{pmtct_known_results_less_than_15}\n pmtct_known_results_between_15_19: #{pmtct_known_results_between_15_19}\n pmtct_known_results_between_20_24: #{pmtct_known_results_between_20_24}\n pmtct_known_results_between_25_49: #{pmtct_known_results_between_25_49}\n pmtct_known_results_more_than_50: #{pmtct_known_results_more_than_50}\n\n"
    $resultsOutput  << "HIV status known at entry results..........................................................\n"
    $resultsOutput  << " total_hiv_status_known_at_entry_positive: #{total_hiv_status_known_at_entry_positive}\n hiv_status_known_at_entry_positive_less_than_15: #{hiv_status_known_at_entry_positive_less_than_15}\n hiv_status_known_at_entry_positive_between_15_19: #{hiv_status_known_at_entry_positive_between_15_19}\n hiv_status_known_at_entry_positive_between_20_24: #{hiv_status_known_at_entry_positive_between_20_24}\n hiv_status_known_at_entry_positive_between_25_49: #{hiv_status_known_at_entry_positive_between_25_49}\n hiv_status_known_at_entry_positive_more_than_50: #{hiv_status_known_at_entry_positive_more_than_50}\n"
  end

  if CDCDataExtraction == 1
    $resultsOutput.close()
  end
end

def self.pmtct_known_results(start_date, end_date, min_age = nil, max_age = nil)
  if (max_age.blank? && min_age.blank?)
    condition = ""
  elsif (max_age.blank?)
    condition = "HAVING age  >= #{min_age}"
  else
    condition = "HAVING age BETWEEN #{min_age} and #{max_age}"
  end

  #HIV status = 3753
  #positive = 703
  pmtct_with_known_results = ActiveRecord::Base.connection.select_all <<EOF
    SELECT o.person_id, p.birthdate, p.gender, (SELECT timestampdiff(year, p.birthdate, DATE(o.obs_datetime))) AS age, DATE(o.obs_datetime), value_text
    FROM obs o
     INNER JOIN person p on p.person_id = o.person_id AND p.voided = 0
    WHERE o.concept_id = 3753 AND o.voided = 0
    AND DATE(o.obs_datetime) <= '#{end_date}'
    AND DATE(o.obs_datetime) = (SELECT MIN(DATE(obs.obs_datetime))
    							FROM obs obs
    							WHERE obs.concept_id = 3753 AND obs.voided = 0
                                AND obs.person_id = o.person_id
                                AND DATE(obs.obs_datetime) <= '#{end_date}'
    							AND (obs.value_text = 'Positive' OR obs.value_coded = 703))
   GROUP BY o.person_id
    #{condition};
EOF

  if pmtct_with_known_results.blank?
    result = 0
  else
    result = pmtct_with_known_results.count
  end
  return  result
end

def self.newly_registered_pmtct_known_results(start_date, end_date, min_age = nil, max_age = nil)
  if (max_age.blank? && min_age.blank?)
    condition = ""
  elsif (max_age.blank?)
    condition = "HAVING age  >= #{min_age}"
  else
    condition = "HAVING age BETWEEN #{min_age} and #{max_age}"
  end

  #HIV status = 3753
  #positive = 703
  pmtct_with_known_results = ActiveRecord::Base.connection.select_all <<EOF
    SELECT o.person_id, p.birthdate, p.gender, (SELECT timestampdiff(year, p.birthdate, DATE(o.obs_datetime))) AS age, DATE(o.obs_datetime), value_text
    FROM obs o
     INNER JOIN person p on p.person_id = o.person_id AND p.voided = 0
    WHERE o.concept_id = 3753 AND o.voided = 0
    AND DATE(o.obs_datetime) BETWEEN '#{start_date}' AND '#{end_date}'
    AND DATE(o.obs_datetime) = (SELECT MIN(DATE(obs.obs_datetime))
    							FROM obs obs
    							WHERE obs.concept_id = 3753 AND obs.voided = 0
                                AND obs.person_id = o.person_id
                                AND DATE(obs.obs_datetime) BETWEEN '#{start_date}' AND '#{end_date}'
    							AND (obs.value_text = 'Positive' OR obs.value_coded = 703))
    GROUP BY o.person_id
    #{condition};
EOF

  if pmtct_with_known_results.blank?
    result = 0
  else
    result = pmtct_with_known_results.count
  end
  return  result
end

def self.hiv_status_known_at_entry_positive(start_date, end_date, min_age = nil, max_age = nil)
  if (max_age.blank? && min_age.blank?)
    condition = ""
  elsif (max_age.blank?)
    condition = " AND age  >= #{min_age}"
  else
    condition = "AND (age BETWEEN #{min_age} and #{max_age})"
  end

  hiv_status_concept_id = 3753 #(SELECT concept_id FROM concept_name WHERE name = 'HIV status' LIMIT 1)
  positive_concept_id = 703 #(SELECT concept_id FROM concept_name WHERE name = 'Positive' LIMIT 1)
  hiv_test_date_concept_id = 1837 #(SELECT concept_id FROM concept_name WHERE name = 'HIV test date' LIMIT 1)

  hiv_status_known_at_entry_positive_results = ActiveRecord::Base.connection.select_all <<EOF
    SELECT
      e.patient_id,
      p.birthdate, p.gender, (SELECT timestampdiff(year, p.birthdate, DATE(o.obs_datetime))) AS age,
      e.encounter_datetime AS date,
      (SELECT value_datetime FROM obs
       WHERE encounter_id = e.encounter_id AND obs.concept_id = #{hiv_test_date_concept_id}) AS test_date
    FROM encounter e
      INNER JOIN obs o ON o.encounter_id = e.encounter_id AND e.voided = 0
      INNER JOIN person p on p.person_id = o.person_id and p.voided = 0
    WHERE o.concept_id = #{hiv_status_concept_id}
    AND ((o.value_coded = #{positive_concept_id}) OR (o.value_text = 'Positive'))
    AND e.encounter_id = (SELECT MAX(encounter.encounter_id) FROM encounter
                           INNER JOIN obs ON obs.encounter_id = encounter.encounter_id
                            AND obs.concept_id = (SELECT concept_id FROM concept_name WHERE name = 'HIV test date' LIMIT 1)
                          WHERE encounter_type = e.encounter_type AND patient_id = e.patient_id
                          AND DATE(encounter.encounter_datetime) <= '#{end_date}')
    AND (DATE(e.encounter_datetime) <= '#{end_date}')
    GROUP BY e.patient_id
    HAVING DATE(date) = DATE(test_date) #{condition};
EOF

  if hiv_status_known_at_entry_positive_results.blank?
    result = 0
  else
    result = hiv_status_known_at_entry_positive_results.count
  end
  return  result
end

start
