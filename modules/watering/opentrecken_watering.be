#
#  reads value from a analog input (sensor) and switches a power output (Pump) on for a given time
#

var opentrecken_watering = module('opentrecken_watering')
var opentrecken_watering_version = "v0.0.2"
class opentrecken_watering
  
  var sensor_value  # current sensor value, set via rule
  var pump_state    # boolean of the state of the pump 
  var configured_rule_name # string with the name of the sensor read rule, when added

  def init()
    import persist
    var conf = self.read_persist()

    # init the sensor value with a 'invalid' value
    self.sensor_value = -1
    self.pump_state = false
    self.configured_rule_name = ""

    if size(conf.ot_watering_sensor_gpio) > 0
          self.add_rule(conf.ot_watering_sensor_gpio)
    end
   
  end


  # ####################################################################################################
  # registers a rule to get the sensor value of the configured analog input
  # ####################################################################################################
  def add_rule(named_input)
    tasmota.add_rule(named_input, def (value, trigger) self.trigger_sensor_value_changed(value, trigger) end)
    self.configured_rule_name = named_input
  end

  # ####################################################################################################
  # deletes a registered rule
  # ####################################################################################################
  def delete_rule()
    tasmota.remove_rule(self.configured_rule_name)
  end

  def trigger_sensor_value_changed(value, trigger)
    self.sensor_value = value
    self.evaluate()
  end

  # ####################################################################################################
  # Evaluate if the sensor has a value in the configured range and the pump has to be turned on
  # ####################################################################################################
  def evaluate()
    # read configuration
    var conf = self.read_persist()
    if conf.ot_watering_active == true
      # we are supposed to control the pump
      try
        # raise a error when the sensor value is invalid (-1)
        assert(self.sensor_value >= 0, "invalid sensor value " + str(self.sensor_value))

        # test if the sensor value is in the range
        if self.sensor_value >= conf.ot_watering_sensor_range_min && self.sensor_value <= conf.ot_watering_sensor_range_max
          # the sensor value is in the range, so we turn the pump on 
          self.pump_on()

        else
          #print("the sensor value of '" + str(self.sensor_value) + "' is not in the range of '" + str(conf.ot_watering_sensor_range_min) + "'-'" + str(conf.ot_watering_sensor_range_max) + "'.")  
        end
      except .. as e, m
        print(format("evaluate: Exception> '%s' - %s", e, m))
        # as safety feature: turn the pump of if a error happend
        self.pump_off()
      end
      
      # set the timer for the next evaluation
      #tasmota.set_timer(conf.ot_watering_evaluate_interval, def () self.evaluate() end)
    else
      # when ot_watering_active is set to false we only set a interval to check it again at a fixed interval
      # fixed interval because that will also work, if the device hasnt any config.
      #tasmota.set_timer(3000, def () self.evaluate() end)
    end
  end

  # ####################################################################################################
  # turns pump off
  # ####################################################################################################
  def pump_off()

    # read configuration
    var conf = self.read_persist()
    # turn off the pin
    tasmota.set_power(conf.ot_watering_pump_gpio, false)

    # set our internal state of the pump
    self.pump_state = false
  end

  # ####################################################################################################
  # turns pump on
  # ####################################################################################################
  def pump_on()

    # read configuration
    var conf = self.read_persist()
    if self.pump_state == false # only when the pump is not running already

      # set our internal state of the pump
      self.pump_state = true
      
      # turn on the pin
      tasmota.set_power(conf.ot_watering_pump_gpio, true)
      
      # and set a timer to turn it of again after the duty time
      tasmota.set_timer(conf.ot_watering_dutycycle, def () self.pump_off() end)
    end
  end


  # ####################################################################################################
  # Init web handlers
  # ####################################################################################################
  # Displays a button on the configuration menu
  def web_add_config_button()
    import webserver
    webserver.content_send("<p><form id=opentrecken_watering action='opentrecken_watering' style='display: block;' method='get'><button>Configure Watering</button></form></p>")
  end

  # ####################################################################################################
  # Get Sensor gpios
  #
  # Returns an array of valid sensor gpios as defined in the template, or empty array
  # ####################################################################################################
  def get_sensor_gpios()
    import json
    var sensors = json.load(tasmota.read_sensors())
    var ret = []
    if sensors != nil && sensors.contains("ANALOG")
      for i: sensors["ANALOG"].keys()
        var o = "ANALOG#" + str(i)
        ret.push(o)
      end
    end

    if sensors != nil && sensors.contains("ADS1115")
      for i: sensors["ADS1115"].keys()
        var o = "ADS1115#" + str(i)
        ret.push(o)
      end
    end
    return ret
  end

  # ####################################################################################################
  # Get Pump gpios
  #
  # Returns an array of valid pump gpios as defined in the template, or empty array
  # ####################################################################################################
  def get_pump_gpios()
    var ret = []
    if size(tasmota.get_power()) > 0
      for p:0..(size(tasmota.get_power())-1)
          ret.push(p)
      end
    end
    return ret
  end
  # ####################################################################################################
  # reads stored config from the json in the filesystem
  # ####################################################################################################
  static def read_persist()
    import persist
    var conf = dyn()

    conf.ot_watering_active = persist.find("ot_watering_active", false) 
    conf.ot_watering_debug = persist.find("ot_watering_debug", false) 
    conf.ot_watering_sensor_gpio = persist.find("ot_watering_sensor_gpio", "") 
    conf.ot_watering_pump_gpio = persist.find("ot_watering_pump_gpio", 0) 
    conf.ot_watering_sensor_range_min = persist.find("ot_watering_sensor_range_min", 0) 
    conf.ot_watering_sensor_range_max = persist.find("ot_watering_sensor_range_max", 100) 
    conf.ot_watering_dutycycle = persist.find("ot_watering_dutycycle", 500) 
    return conf
  end

  # ####################################################################################################
  # saves config to the json in the filesystem
  # ####################################################################################################
  def save_persist(conf)
    import persist
    persist.ot_watering_active = conf.ot_watering_active
    persist.ot_watering_debug = conf.ot_watering_debug
    persist.ot_watering_sensor_gpio = conf.ot_watering_sensor_gpio
    persist.ot_watering_pump_gpio = conf.ot_watering_pump_gpio
    persist.ot_watering_sensor_range_min = conf.ot_watering_sensor_range_min
    persist.ot_watering_sensor_range_max = conf.ot_watering_sensor_range_max
    persist.ot_watering_dutycycle = conf.ot_watering_dutycycle
    persist.save()
  end

  #######################################################################
  # Display the complete page on `/opentrecken_watering`
  #######################################################################
  def page_opentrecken_watering()
    import webserver
    if !webserver.check_privileged_access() return nil end

    # read configuration
    var conf = self.read_persist()

    webserver.content_start("Watering")           #- title of the web page -#
    webserver.content_send_style()                #- send standard Tasmota styles -#
    webserver.content_send("<fieldset><legend><b> Watering configuration </b></legend>")
    webserver.content_send("<form action='/opentrecken_watering' method='post'>")

    # Sensor configuration
    webserver.content_send(format("<p><b>Sensor:</b></br>"))
    var sensor_list = self.get_sensor_gpios()
    if size(sensor_list) == 0
      webserver.content_send("<b>**Not configured**</b>")
    else
      webserver.content_send("<select id='ot_watering_sensor_gpio'>")
      for gp:sensor_list
        var selected = ""
        if conf.ot_watering_sensor_gpio == gp
          selected = " selected"
        end
        webserver.content_send(format("<option value='%s' %s>%s</option>", gp, selected, gp))
      end
      webserver.content_send("</select>")
    end
    webserver.content_send("</p>")

    # Pump configuration
    webserver.content_send(format("<p><b>Pump:</b></br>"))
    var pump_list = self.get_pump_gpios()
    if size(pump_list) == 0
      webserver.content_send("<b>**Not configured**</b>")
    else
      webserver.content_send("<select id='ot_watering_pump_gpio'>")
      for gp:pump_list
        var selected = ""
        if conf.ot_watering_pump_gpio == gp
          selected = " selected"
        end
        webserver.content_send(format("<option value='%i' %s>%s</option>", gp, selected, str(gp+1)))
      end
      webserver.content_send("</select>")
    end
    webserver.content_send("</p>")


    
    # ot_watering_active
    webserver.content_send(format("<p><b>Active:</b></br><input type='checkbox' name='ot_watering_active' %s></p>", conf.ot_watering_active ? " checked" : ""))

    # ot_watering_debug
    webserver.content_send(format("<p><b>Debug:</b></br><input type='checkbox' name='ot_watering_debug' %s></p>", conf.ot_watering_debug ? " checked" : ""))

    # ot_watering_sensor_range_min
    webserver.content_send(format("<p><b>Sensor range min:</b></br>"))
    webserver.content_send(format("<input type='number' min='0' name='ot_watering_sensor_range_min' value='%i'>", conf.ot_watering_sensor_range_min))
    webserver.content_send("</p>")

    # ot_watering_sensor_range_max
    webserver.content_send(format("<p><b>Sensor range max:</b></br>"))
    webserver.content_send(format("<input type='number' min='0' name='ot_watering_sensor_range_max' value='%i'>", conf.ot_watering_sensor_range_max))
    webserver.content_send("</p>")

    # ot_watering_dutycycle
    webserver.content_send(format("<p><b>Dutycycle:</b></br>"))
    webserver.content_send(format("<input type='number' min='0' name='ot_watering_dutycycle' value='%i'>", conf.ot_watering_dutycycle))
    webserver.content_send("</p>")

    webserver.content_send(format("<p><b>Version:</b></br>%s</p>", opentrecken_watering_version))


    # button
    webserver.content_send("<button name='opentreckenapply' class='button bgrn'>Save</button>")
    webserver.content_send("</form>")
    webserver.content_send("</fieldset>")
    webserver.content_button(webserver.BUTTON_CONFIGURATION)
    webserver.content_stop()
  end

  #######################################################################
  # Web Controller, called by POST to `/opentrecken_watering`
  #######################################################################
  def page_opentrecken_ctl()
    import webserver
    if !webserver.check_privileged_access() return nil end

    import persist
    import introspect
    
    try
      if webserver.has_arg("opentreckenapply")
        # read argumments, sanity check and put in conf object
        var conf = dyn()
        
        var ot_watering_sensor_gpio_list = self.get_sensor_gpios()
        var ot_watering_sensor_gpio = webserver.arg("ot_watering_sensor_gpio")
        assert(ot_watering_sensor_gpio_list.find(ot_watering_sensor_gpio) != nil, "ot_watering_sensor_gpio is not in the list of avaiable sensor pins")
        self.delete_rule()  # delete the current rule 
        self.add_rule(ot_watering_sensor_gpio)  # register the new rule
        conf.ot_watering_sensor_gpio = ot_watering_sensor_gpio
        

        var ot_watering_pump_gpio_list = self.get_pump_gpios()
        var ot_watering_pump_gpio = int(webserver.arg("ot_watering_pump_gpio"))
        if ot_watering_pump_gpio_list.find(ot_watering_pump_gpio) != nil
          conf.ot_watering_pump_gpio = ot_watering_pump_gpio
        else
          conf.ot_watering_pump_gpio = -1
        end
        
        #
        conf.ot_watering_active = webserver.arg("ot_watering_active") == 'on'
        
        #
        conf.ot_watering_debug = webserver.arg("ot_watering_debug") == 'on'

        #
        var ot_watering_sensor_range_min = int(webserver.arg("ot_watering_sensor_range_min"))
        assert(ot_watering_sensor_range_min >= 0, "ot_watering_sensor_range_min cant be lower than 0")
        assert(ot_watering_sensor_range_min < 65335, "ot_watering_sensor_range_min cant be greater than 65335")
        conf.ot_watering_sensor_range_min = ot_watering_sensor_range_min
        
        #
        var ot_watering_sensor_range_max = int(webserver.arg("ot_watering_sensor_range_max"))
        assert(ot_watering_sensor_range_max >= 0, "ot_watering_sensor_range_max cant be lower than 0")
        assert(ot_watering_sensor_range_max < 65335, "ot_watering_sensor_range_max cant be greater than 65335")
        conf.ot_watering_sensor_range_max = ot_watering_sensor_range_max
        
        # check if the min value is equal or greater to the max
        assert(ot_watering_sensor_range_max > ot_watering_sensor_range_min, "ot_watering_sensor_range_min cant be greater or equal as ot_watering_sensor_range_max")
        

        var ot_watering_dutycycle = int(webserver.arg("ot_watering_dutycycle"))
        assert(ot_watering_dutycycle >= 0, "ot_watering_dutycycle cant be lower than 0")
        assert(ot_watering_dutycycle < 65335, "ot_watering_dutycycle cant be greater than 65335")
        conf.ot_watering_dutycycle = ot_watering_dutycycle

        self.save_persist(conf)

        print("config saved: conf=" + str(conf), 2);
        webserver.redirect("/cn?")
      else
        raise "value_error", "Unknown command"
      end
    except .. as e, m
      print(format("BRY: Exception> '%s' - %s", e, m))
      #- display error page -#
      webserver.content_start("Parameter error")      #- title of the web page -#
      webserver.content_send_style()                  #- send standard Tasmota styles -#
      webserver.content_send(format("<p style='width:340px;'><b>Exception:</b><br>'%s'<br>%s</p>", e, m))
      webserver.content_button(webserver.BUTTON_CONFIGURATION) #- button back to management page -#
      webserver.content_stop()                        #- end of web page -#
    end
  end

  #- ---------------------------------------------------------------------- -#
  # respond to web_add_handler() event to register web listeners
  #- ---------------------------------------------------------------------- -#
  #- this is called at Tasmota start-up, as soon as Wifi/Eth is up and web server running -#
  def web_add_handler()
    import webserver
    #- we need to register a closure, not just a function, that captures the current instance -#
    webserver.on("/opentrecken_watering", / -> self.page_opentrecken_watering(), webserver.HTTP_GET)
    webserver.on("/opentrecken_watering", / -> self.page_opentrecken_ctl(), webserver.HTTP_POST)
  end

end

#- create and register driver in Tasmota -#
if tasmota
  var opentrecken_watering_instance = opentrecken_watering()
  tasmota.add_driver(opentrecken_watering_instance)
  opentrecken_watering_instance.web_add_handler()
end
  
return opentrecken_watering