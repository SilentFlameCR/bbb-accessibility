#!/usr/bin/ruby
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 3.0 of the License, or (at your option)
# any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require "trollop"

require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
end
$meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

$published_files = "/var/bigbluebutton/published/presentation/#{$meeting_id}"
$archived_files = "/var/bigbluebutton/recording/raw/#{$meeting_id}"
$meeting_metadata = BigBlueButton::Events.get_meeting_metadata("/var/bigbluebutton/recording/raw/#{$meeting_id}/events.xml")
$events_xml = "#{$archived_files}/events.xml"
$audio_dir = "#{$archived_files}/audio"
#$published_files_video = "/var/bigbluebutton/published/presentation/#{$meeting_id}/video"
#$scripts = "/usr/local/bigbluebutton/core/scripts/post_publish"

############################CUSTOM SCRIPT STARTS HERE#######################################
#require 'rubygems'
#require "google/cloud"
#require "streamio-ffmpeg"
require "google/cloud/speech"
require "google/cloud/storage"

#web_captions = File.open("#{$published_files}/captions.vtt", "w")
#web_captions.puts("WEBVTT\n\n")

ENV['GOOGLE_APPLICATION_CREDENTIALS'] = '/usr/local/bigbluebutton/core/scripts/post_publish/bbb-accessibility-183f2b339bfb.json'

$transcribe = {
    "service" => "google"
}

#def video_to_audio
def video_to_audio
  video_to_audio_command = "ffmpeg -i #{$published_files}/video/webcams.webm -ac 1 -ar 16000 #{$published_files}/#{$meeting_id}.flac"
  system("#{video_to_audio_command}")
end

#uploads audio file to a google bucket
def google_storage
  storage = Google::Cloud::Storage.new project_id: "bbb-accessibility"
  $bucket  = storage.bucket "bbb-accessibility"
  file = $bucket.create_file "#{$published_files}/#{$meeting_id}.flac", "#{$meeting_id}.flac"
end

#function to convert the time to a timestamp
def seconds_to_timestamp number
  ss = number
  mm = ss / 60
  hh = (number/3600).floor
  number = number % 3600
  mm = (number / 60).floor
  ss = (number % 60).round(3)
  if ss < 10
    ss = "0#{ss.to_s}"
  end
  parts = ss.to_s.split(".")
  if parts.length > 1
    1.upto (3-parts[1].length) {parts[1] = parts[1].concat("0")}
    ss = "#{parts[0]}.#{parts[1]}"
  else
        ss = parts[0].concat(".000")
  end
  if mm < 10
    mm = "0#{mm.to_s}"
  end
  if hh < 10
    hh = "0#{hh.to_s}"
  end
  return "#{hh}:#{mm}:#{ss}"
end

#create and write the webvtt file
def write_to_webvtt myarray

  filename = "#{$published_files}/caption_en_US.vtt"
  file = File.open(filename,"w")
  file.puts ("WEBVTT\n\n")

  i=0

  while(i<myarray.length)

    file.puts i/30 + 1
    if i+28 < myarray.length
      file.puts "#{seconds_to_timestamp myarray[i]} --> #{seconds_to_timestamp myarray[i+28]}"
      file.puts "#{myarray[i+2]} #{myarray[i+5]} #{myarray[i+8]} #{myarray[i+11]} #{myarray[i+14]}"
      file.puts "#{myarray[i+17]} #{myarray[i+20]} #{myarray[i+23]} #{myarray[i+26]} #{myarray[i+29]}\n\n"
    else
      remainder = myarray.length - i
      file.puts "#{seconds_to_timestamp myarray[i]} --> #{seconds_to_timestamp myarray[myarray.length-2]}"
      count = 0
      flag = true
      while (count < remainder )
        file.print "#{myarray[i+2]} "
        if flag
          if count > 9
            file.print "\n"
            flag = false
          end
        end
        i+=3
        count+=3
      end
    end
    i = i + 30
  end

  captions_file_name = "#{$published_files}/captions.json"
  captions_file = File.open(captions_file_name,"w")
  captions_file.puts ("[{\"localeName\": \"English (United States)\", \"locale\": \"en_US\"}]")
end

#create an array with the start time, stop time and words
def create_array_google results
  data_array = []
  results.each do |result|

    result.alternatives.each do |alternative|
      #puts "Transcription: #{alternative.transcript}"

      #file.puts("#{alternative.transcript}")
      
      alternative.words.each_with_index do |word, i|
        start_time = word.start_time.seconds + word.start_time.nanos/1000000000.0
        end_time   = word.end_time.seconds + word.end_time.nanos/1000000000.0

        #start_time_array.push(seconds_to_timestamp(start_time))
        #end_time_array.push(seconds_to_timestamp(end_time))
        #words_array.push(word.word)
        data_array.push(start_time)
        data_array.push(end_time)
        data_array.push(word.word)
        
      end 
      
    end

  end
  return data_array
end

def create_array_watson data
  k = 0
  myarray = []
  while k!= data["results"].length
    j = 0
    while j!= data["results"][k]["alternatives"].length
      i = 0
      while i!= data["results"][k]["alternatives"][j]["timestamps"].length
        first = data["results"][k]["alternatives"][j]["timestamps"][i][1]
        last = data["results"][k]["alternatives"][j]["timestamps"][i][2]
        transcript = data["results"][k]["alternatives"][j]["timestamps"][i][0]

        if transcript.include? "%HESITATION"
            transcript["%HESITATION"] = ""
        end
        myarray.push(first)
        myarray.push(last)
        myarray.push(transcript)
        i+=1
      end
      confidence = data["results"][k]["alternatives"][j]["confidence"]
      myarray[myarray.length-2] = myarray[myarray.length-2] + confidence
    j+=1
    end

  k+=1
  end

  return myarray
end

#return the results from google speech
def google_transcription
  # Instantiates a client
  speech = Google::Cloud::Speech.new

  # The name of the audio file to transcribe
  #file_name = "#{$published_files}/#{$meeting_id}.flac" #only needed when using locally

  # The raw audio
  #audio_file = File.binread file_name #only needed when using locally

  # The audio file's encoding and sample rate
  config = { encoding:          :FLAC,
             sample_rate_hertz: 16000,#transcoded_movie.audio_sample_rate,
             language_code:     "en-US",
             enable_word_time_offsets: true }
  audio  = { #content: audio_file #using local audio file
             #uri: "gs://bbb-accessibility/video.FLAC" #static bucket file usage
             uri: "gs://bbb-accessibility/#{$meeting_id}.flac" #using the now uploaded audio file from the bucket
           }

  # Detects speech in the audio file
  operation = speech.long_running_recognize config, audio

  #puts "Operation started"

  operation.wait_until_done!

  raise operation.results.message if operation.error?

  results = operation.response.results
  return results
end

#delete uploaded audio file from the google bucket
def google_delete
  file = $bucket.file "#{$meeting_id}.flac"

  file.delete
end

#Google-speech-to-text function
def google_speech_to_text
  #video_to_audio
  google_storage
  results = google_transcription

  data_array = create_array_google(results)
  write_to_webvtt(data_array)
  google_delete

end

def watson_speech_to_text
  require 'json'
  jsonfile_path = "#{$published_files}/audio.json"
  #video_to_audio
  watson_command = "curl -X POST -u \"apikey:hEieEKi5ABhGYY01FYLh7swZcghEw3izdpan3Piqpa5V\" --header \"Content-Type: audio/flac\" --data-binary @#{$published_files}/#{$meeting_id}.flac \"https://stream.watsonplatform.net/speech-to-text/api/v1/recognize?timestamps=true\" > #{jsonfile_path}"
  system("#{watson_command}")
  out = File.open(jsonfile_path, "r")
  data = JSON.load out

  myarray = create_array_watson data
  write_to_webvtt myarray
end

#if !File.exist("#{$published_files}/#{$meeting_id}.flac")
    video_to_audio
#end
if $transcribe["service"] === "google"
    google_speech_to_text
elsif $transcribe["service"] === "ibm"
    watson_speech_to_text
else
    BigBlueButton.logger.info("No valid speech-to-text service selected")
    exit 1  
end



exit 0



