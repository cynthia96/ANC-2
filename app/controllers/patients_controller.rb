class PatientsController < ApplicationController
  before_filter :find_patient, :except => [:void]
  
  def show  
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    
    @current_range = active_range(@patient.id, (session[:datetime] ? session[:datetime].to_date : Date.today)) rescue nil

    @encounters = @patient.encounters.active.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
        @current_range[0]["START"], @current_range[0]["END"]]) rescue []
    
    @encounter_names = @patient.encounters.active.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
        @current_range[0]["START"], @current_range[0]["END"]]).map{|encounter| encounter.name}.uniq rescue []

    @names = @encounters.collect{|e|
      e.name
    }
    
    render :layout => 'dynamic-dashboard'
  end

  def treatment
    #@prescriptions = @patient.orders.current.prescriptions.all
    type = EncounterType.find_by_name('TREATMENT')
    session_date = session[:datetime].to_date rescue Date.today
    @prescriptions = Order.find(:all,
      :joins => "INNER JOIN encounter e USING (encounter_id)",
      :conditions => ["encounter_type = ? AND e.patient_id = ? AND DATE(encounter_datetime) = ?",
        type.id,@patient.id,session_date])
    @historical = @patient.orders.historical.prescriptions.all
    @restricted = ProgramLocationRestriction.all(:conditions => {:location_id => Location.current_health_center.id })
    @restricted.each do |restriction|
      @prescriptions = restriction.filter_orders(@prescriptions)
      @historical = restriction.filter_orders(@historical)
    end
    render :template => 'dashboards/treatment', :layout => 'dashboard' 
  end

  def relationships
    if @patient.blank?
    	redirect_to :'clinic'
    	return
    else
      next_form = next_task(@patient)
      redirect_to next_form and return if next_form.match(/Reception/i)
		  @relationships = @patient.relationships rescue []
		  @restricted = ProgramLocationRestriction.all(:conditions => {:location_id => Location.current_health_center.id })
		  @restricted.each do |restriction|
		    @relationships = restriction.filter_relationships(@relationships)
		  end
    	render :template => 'dashboards/relationships', :layout => 'dashboard' 
  	end
  end

  def problems
    render :template => 'dashboards/problems', :layout => 'dashboard' 
  end

  def personal
    render :template => 'dashboards/personal', :layout => 'dashboard' 
  end

  def history
    render :template => 'dashboards/history', :layout => 'dashboard' 
  end

  def programs
    @programs = @patient.patient_programs.all
    @restricted = ProgramLocationRestriction.all(:conditions => {:location_id => Location.current_health_center.id })
    @restricted.each do |restriction|
      @programs = restriction.filter_programs(@programs)
    end
    flash.now[:error] = params[:error] unless params[:error].blank?
    render :template => 'dashboards/programs', :layout => 'dashboard' 
  end

  def graph
    render :template => "graphs/#{params[:data]}", :layout => false 
  end

  def void 
    @encounter = Encounter.find(params[:encounter_id])
    @patient = @encounter.patient
    @encounter.void
    redirect_to "/patients/tab_visit_summary/?patient_id=#{@patient.id}" and return
  end

  def print_registration
    print_and_redirect("/patients/national_id_label/?patient_id=#{@patient.id}", next_task(@patient))  
  end

  def print_visit
    print_and_redirect("/patients/visit_label/?patient_id=#{@patient.id}", next_task(@patient))  
  end

  def print_mastercard_record
    print_and_redirect("/patients/mastercard_record_label/?patient_id=#{@patient.id}&date=#{params[:date]}", "/patients/visit?date=#{params[:date]}&patient_id=#{params[:patient_id]}")  
  end

  def national_id_label
    print_string = @patient.national_id_label rescue (raise "Unable to find patient (#{params[:patient_id]}) or generate a national id label for that patient")
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end

  def visit_label
    print_string = @patient.visit_label rescue (raise "Unable to find patient (#{params[:patient_id]}) or generate a visit label for that patient")
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end

  def mastercard_record_label
    print_string = @patient.visit_label(params[:date].to_date) 
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end

  def mastercard
    #the parameter are used to re-construct the url when the mastercard is called from a Data cleaning report
    @quarter = params[:quarter]
    @arv_start_number = params[:arv_start_number]
    @arv_end_number = params[:arv_end_number]
    @show_mastercard_counter = false
    
    if params[:patient_id].blank?

      @show_mastercard_counter = true

      if !params[:current].blank?
        session[:mastercard_counter] = params[:current].to_i - 1
      end
      @prev_button_class = "yellow"
      @next_button_class = "yellow"
      if params[:current].to_i ==  1
        @prev_button_class = "gray"
      elsif params[:current].to_i ==  session[:mastercard_ids].length
        @next_button_class = "gray"
      else

      end
      @patient_id = session[:mastercard_ids][session[:mastercard_counter]]
      @data_demo = Mastercard.demographics(Patient.find(@patient_id))
      @visits = Mastercard.visits(Patient.find(@patient_id))

    elsif session[:mastercard_ids].length.to_i != 0
      @patient_id = params[:patient_id]
      @data_demo = Mastercard.demographics(Patient.find(@patient_id))
      @visits = Mastercard.visits(Patient.find(@patient_id))
    else
      @patient_id = params[:patient_id]
      @data_demo = Mastercard.demographics(Patient.find(@patient_id))
      @visits = Mastercard.visits(Patient.find(@patient_id))
    end
    render :layout => "menu"
  end
  
  def visit
    @patient_id = params[:patient_id] 
    @date = params[:date].to_date
    @patient = Patient.find(@patient_id)
    @visits = Mastercard.visits(@patient,@date)
    render :layout => "summary"
  end

  def next_available_arv_number
    next_available_arv_number = PatientIdentifier.next_available_arv_number
    render :text => next_available_arv_number.gsub(Location.current_arv_code,'').strip rescue nil
  end
  
  def assigned_arv_number
    assigned_arv_number = PatientIdentifier.find(:all,:conditions => ["voided = 0 AND identifier_type = ?",
        PatientIdentifierType.find_by_name("ARV Number").id]).collect{|i|
      i.identifier.gsub(Location.current_arv_code,'').strip.to_i
    } rescue nil
    render :text => assigned_arv_number.sort.to_json rescue nil 
  end

  def mastercard_modify
    if request.method == :get
      @patient_id = params[:id]
      case params[:field]
      when 'arv_number'
        @edit_page = "arv_number"
      when "name"
      end
    else
      @patient_id = params[:patient_id]
      case params[:field]
      when 'arv_number'
        type = params['identifiers'][0][:identifier_type]
        patient = Patient.find(params[:patient_id])
        patient_identifiers = PatientIdentifier.find(:all,
          :conditions => ["voided = 0 AND identifier_type = ? AND patient_id = ?",type.to_i,patient.id])

        patient_identifiers.map{|identifier|
          identifier.voided = 1
          identifier.void_reason = "given another number"
          identifier.date_voided  = Time.now()
          identifier.voided_by = User.current_user.id
          identifier.save
        }
              
        identifier = params['identifiers'][0][:identifier].strip
        if identifier.match(/(.*)[A-Z]/i).blank?
          params['identifiers'][0][:identifier] = "#{Location.current_arv_code} #{identifier}"
        end
        patient.patient_identifiers.create(params[:identifiers])
        redirect_to :action => "mastercard",:patient_id => patient.id and return
      when "name"
      end
    end
  end

  def summary
    @encounter_type = params[:skipped]
    @patient_id = params[:patient_id]
    render :layout => "menu"
  end

  def export_to_csv
    @users = User.find(:all)

    csv_string = FasterCSV.generate do |csv|
      # header row
      csv << ["id", "first_name", "last_name"]

      # data rows
      @users.each do |user|
        csv << [user.id, user.username, user.salt]
      end
    end

    # send it to the browsah
    send_data csv_string,
      :type => 'text/csv; charset=iso-8859-1; header=present',
      :disposition => "attachment; filename=users.csv"
  end
   
  def tab_visit_summary
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    
    @encounters = @patient.encounters.active.find(:all, 
      :conditions => ["DATE(encounter_datetime) = ?", (session[:datetime] ? session[:datetime].to_date : Date.today)]) rescue []
    
    @encounter_names = @encounters.map{|encounter| encounter.name}.uniq rescue []

    render :layout => false
  end

  def tab_obstetric_history
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
     
    @pregnancies = active_range(@patient.id)
    
    @range = []
    
    @pregnancies = @pregnancies[1]
    
    @pregnancies.each{|preg|
      @range << preg[0].to_date
    }
    
    @deliveries = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('PARITY').concept_id]).answer_string.to_i rescue 0

    @deliveries = @deliveries + @range.length
    
    @abortions = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('NUMBER OF ABORTIONS').concept_id]).answer_string.to_i rescue 0

    @stillbirths = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('STILL BIRTH').concept_id]).answer_string rescue nil

    @csections = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('Caesarean section').concept_id]).answer_string rescue nil

    @vacuum = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('Vacuum extraction delivery').concept_id]).answer_string rescue nil

    @symphosio = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('SYMPHYSIOTOMY').concept_id]).answer_string rescue nil

    @haemorrhage = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('HEMORRHAGE').concept_id]).answer_string rescue nil

    @preeclampsia = Observation.find(:last,
      :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
        Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('PRE-ECLAMPSIA').concept_id]).answer_string rescue nil

    render :layout => false
  end

  def tab_medical_history
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    
    @asthma = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('ASTHMA').concept_id]).answer_string rescue nil

    @hyper = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('HYPERTENSION').concept_id]).answer_string rescue nil

    @diabetes = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('DIABETES').concept_id]).answer_string rescue nil

    @epilepsy = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('EPILEPSY').concept_id]).answer_string rescue nil

    @renal = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('RENAL DISEASE').concept_id]).answer_string rescue nil

    @fistula = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('FISTULA REPAIR').concept_id]).answer_string rescue nil

    @deform = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('SPINE OR LEG DEFORM').concept_id]).answer_string rescue nil

    @age = @patient.age rescue 0

    render :layout => false
  end    

  def tab_examinations_management
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil

    @height = @patient.current_height.to_i

    @multiple = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('EVER HAD A MULTIPLE PREGNANCY?').concept_id]).answer_string rescue nil

    @who = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
        @patient.id, Encounter.active.find(:all).collect{|e| e.encounter_id},
        ConceptName.find_by_name('WHO CLINICAL STAGE').concept_id]).answer_string.to_i rescue nil

    render :layout => false
  end

  def tab_lab_results
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil

    syphil = {}
    @patient.encounters.find(:all, :conditions => ["encounter_type IN (?)", 
        EncounterType.find_by_name("CURRENT PREGNANCY").id]).each{|e| 
      e.observations.active.each{|o| 
        syphil[o.concept.name.name] = o.answer_string
      }      
    }
    
    @syphilis = syphil["SYPHILIS TEST RESULT"].titleize rescue nil

    @syphilis_date = syphil["SYPHILIS TEST RESULT DATE"] rescue nil

    hb = {}; pos = 1; 
    
    @patient.encounters.active.find(:all, 
      :order => "encounter_datetime DESC", :conditions => ["encounter_type = ?", 
        EncounterType.find_by_name("LAB RESULTS").id]).each{|e| 
      e.observations.active.each{|o| hb[o.concept.name.name + " " + 
            pos.to_s] = o.answer_string; pos += 1 if o.concept.name.name == "HB TEST RESULT DATE";
      }      
    }
    
    @hb1 = hb["HB TEST RESULT 1"] rescue nil

    @hb1_date = hb["HB TEST RESULT DATE 1"] rescue nil

    @hb2 = hb["HB TEST RESULT 2"] rescue nil

    @hb2_date = hb["HB TEST RESULT DATE 2"] rescue nil

    @cd4 = syphil['CD4 COUNT'] rescue nil

    @cd4_date = syphil['CD4 COUNT DATETIME'] rescue nil

    render :layout => false
  end

  def tab_visit_history
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
  
    @current_range = active_range(@patient.id, (params[:target_date] ? 
          params[:target_date].to_date : (session[:datetime] ? session[:datetime].to_date : Date.today)))

    @encounters = {}

    @patient.encounters.active.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
        @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
      @encounters[e.encounter_datetime.strftime("%Y-%m-%d")] = {"USER" => User.find(e.creator).name}    
    }

    @patient.encounters.active.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
        @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
      @encounters[e.encounter_datetime.strftime("%Y-%m-%d")][e.type.name] = {}
    }

    @patient.encounters.active.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
        @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
      e.observations.each{|o| 
        if o.to_a[0] == "DIAGNOSIS" && @encounters[e.encounter_datetime.strftime("%Y-%m-%d")][e.type.name][o.to_a[0]]
          @encounters[e.encounter_datetime.strftime("%Y-%m-%d")][e.type.name][o.to_a[0]] += "; " + o.to_a[1]
        else
          @encounters[e.encounter_datetime.strftime("%Y-%m-%d")][e.type.name][o.to_a[0]] = o.to_a[1]
        end
      }
    }

    @drugs = {}; 
    
    @patient.encounters.active.find(:all, :order => "encounter_datetime DESC", 
      :conditions => ["encounter_type = ? AND encounter_datetime >= ? AND encounter_datetime <= ?", 
        EncounterType.find_by_name("TREATMENT").id, @current_range[0]["START"], @current_range[0]["END"]]).each{|e| 
      @drugs[e.encounter_datetime.strftime("%Y-%m-%d")] = {}; 
      e.orders.each{|o| 
        @drugs[e.encounter_datetime.strftime("%Y-%m-%d")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
      }      
    }
    
    # raise @encounters.to_yaml

    render :layout => false
  end

  def observations
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def preventative_medications
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def hiv_status
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def pmtct_management
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def obstetric_history
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def medical_history
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def examinations_management
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def new
    @patient = Patient.find(params[:patient_id] || session[:patient_id])
  end

  def pregnancy_history
    @patient = Patient.find(params[:patient_id]) rescue nil
    
    @pregnancies = active_range(@patient.id)
    
    @range = []
    
    @pregnancies = @pregnancies[1]
    
    @pregnancies.each{|preg|
      @range << preg[0].to_date
    }
    
    @range = @range.sort.reverse
    
    # raise @range.to_yaml
    
    render :layout => 'dashboard'
  end

  def current_pregnancy
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def outcome
    @patient = Patient.find(params[:patient_id]) rescue nil
  end

  def current_visit
    @patient = Patient.find(params[:patient_id] || session[:patient_id])
    
    @encounters = @patient.encounters.active.find(:all, :conditions => ["encounter_type IN (?) AND " + 
          "DATE_FORMAT(encounter_datetime, '%Y-%m-%d') = ?",
        EncounterType.find(:all, :conditions => ["name in ('OBSERVATIONS', 'VITALS', 'TREATMENT', 'LAB RESULTS', " +
              "'DIAGNOSIS', 'APPOINTMENT')"]).collect{|t| t.id}, 
        (session[:datetime] ? session[:datetime].to_date.strftime("%Y-%m-%d") : Date.today.strftime("%Y-%m-%d"))]).collect{|e|              
      e.type.name
    }.join(", ") # rescue ""

  end

  def demographics
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    @national_id = @patient.national_id_with_dashes rescue nil

    @first_name = @patient.person.names.first.given_name rescue nil
    @last_name = @patient.person.names.first.family_name rescue nil
    @birthdate = @patient.person.birthdate_formatted rescue nil
    @gender = @patient.person.formatted_gender rescue ''

    @current_village = @patient.person.addresses.first.city_village rescue ''
    @current_ta = @patient.person.addresses.first.county_district rescue ''
    @current_district = @patient.person.addresses.first.state_province rescue ''
    @home_district = @patient.person.addresses.first.address2 rescue ''

    @primary_phone = @patient.person.phone_numbers["Cell Phone Number"] rescue ''
    @secondary_phone = @patient.person.phone_numbers["Home Phone Number"] rescue ''

    @occupation = @patient.person.occupation rescue ''
    render :template => 'patients/demographics', :layout => 'menu'

  end

  def edit_demographics
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    @field = params[:field]
    render :partial => "edit_demographics", :field =>@field, :layout => true and return
  end

  def update_demographics
    Person.update_demographics(params)
    redirect_to :action => 'demographics', :patient_id => params['person_id'] and return
  end

  def patient_history
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    
    @encounters = @patient.encounters.active.collect{|e| e.name}
  end

  def tab_detailed_obstetric_history
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    
    @obstetrics = {}
    search_set = ["YEAR OF BIRTH", "PLACE OF BIRTH", "PREGNANCY", "LABOUR DURATION", 
      "METHOD OF DELIVERY", "CONDITION AT BIRTH", "BIRTH WEIGHT", "ALIVE", "AGE AT DEATH"]
    current_level = 0
    
    @patient.encounters.active.collect{|e| 
      e.observations.active.collect{|obs|         
        if search_set.include?(obs.concept.name.name)
          if obs.concept.name.name.eql?("YEAR OF BIRTH")
            current_level += 1
            
            @obstetrics[current_level] = {}
          end
          
          @obstetrics[current_level][obs.concept.name.name] = obs.answer_string
        end
      }      
    }
        
    @pregnancies = active_range(@patient.id)
    
    @range = []
    
    @pregnancies = @pregnancies[1]
    
    @pregnancies.each{|preg|
      @range << preg[0].to_date
    }
    
    @range = @range.sort    
    
    @range.each{|y|
      current_level += 1
      @obstetrics[current_level] = {}
      @obstetrics[current_level]["YEAR OF BIRTH"] = y.year
      @obstetrics[current_level]["PLACE OF BIRTH"] = "<b>(Here)</b>"
    }
    
    render :layout => false
  end
  
  def active_range(patient_id, date = (session[:datetime] ? session[:datetime].to_date : Date.today))    
    patient = Patient.find(patient_id) rescue nil
    
    current_range = {}
    
    active_date = date
      
    pregnancies = {}; 
    
    patient.encounters.active.find(:all, :order => ["encounter_datetime DESC"]).each{|e| 
      if e.name == "CURRENT PREGNANCY" && !pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")]
        pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")] = {}  
        e.observations.each{|o| 
          if o.concept.name.name == "DATE OF LAST MENSTRUAL PERIOD"         
            pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")][o.concept.name.name] = o.answer_string 
          end
        } 
      end      
    }    
    
    pregnancies.each{|preg|
      if preg[1]["DATE OF LAST MENSTRUAL PERIOD"]
        preg[1]["START"] = preg[1]["DATE OF LAST MENSTRUAL PERIOD"].to_date
        preg[1]["END"] = preg[1]["DATE OF LAST MENSTRUAL PERIOD"].to_date + 45.week
      else
        preg[1]["START"] = preg[0].to_date
        preg[1]["END"] = preg[0].to_date + 45.week
      end
      
      if active_date >= preg[1]["START"] && active_date <= preg[1]["END"]
        current_range["START"] = preg[1]["START"]
        current_range["END"] = preg[1]["END"]
      end
    }
    
    return [current_range, pregnancies]
  end
  
  private

end
