# Not Recording :: Microphone -> VolumeNode -> AnalyserNode -> ScriptProcessor -> Destination
#
# Recording :: Microphone -> VolumeNode -> AnalyserNode -> ScriptProcessor -> Recorder -> Destination

class Track
  constructor: (track) ->
    @track  = track
    @canvases = 
      grid: @track.find('canvas#grid')
      wave: @track.find('canvas#wave')
      cursor: @track.find('canvas#cursor')

  leftChannel: []
  rightChannel: []
  length: 0

class Editor

  constructor: (editor, options) ->
    @editor = editor
    @track = new Track(@editor.find('#track'))

    @liveWaveform = @editor.find('#live-waveform')

    @bufferSize = 2048
    @sampleRate = 44100
    [@micRunning, @isRecording] = [false, false]
    [@width, @height, @cursorPosition] = [0, 0, 0]
    @chromaOrange = new chroma.scale(["#00ff00", "#e0e000", "#ff7f00", "#b60101"])
    
    # Setup Web Audio API Context
    @context = new webkitAudioContext()

    @_setupNodes()
    @_setupAudioHandler()
    @_setupClickHandlers()
    @_setupCanvases()
    @_drawGrid()

  ############################################################################################################
  # Web Audio API   
  ############################################################################################################

  _setupNodes: =>
    # Script Processer Node
    # This interface is an AudioNode which can generate, process, or analyse audio directly using JavaScript.
    # https://dvcs.w3.org/hg/audio/raw-file/tip/webaudio/specification.html#ScriptProcessorNode
    @scriptProcessor = @context.createScriptProcessor(2048, 1, 1)
    @scriptProcessor.connect(@context.destination)

    # Analyser Node
    # This interface represents a node which is able to provide real-time frequency and time-domain 
    # analysis information. The audio stream will be passed un-processed from input to output.
    # https://dvcs.w3.org/hg/audio/raw-file/tip/webaudio/specification.html#AnalyserNode-section
    @analyser = @context.createAnalyser()
    @analyser.smoothingTimeConstant = 0
    @analyser.fftSize = 512
    @analyser.connect(@scriptProcessor)

    # Gain Node
    # This interface is an AudioNode with a single input and single output. It multiplies the input audio 
    # signal by the (possibly time-varying) gain attribute, copying the result to the output. By default, 
    # it will take the input and pass it through to the output unchanged, which represents a constant gain 
    # change of 1.
    # https://dvcs.w3.org/hg/audio/raw-file/tip/webaudio/specification.html#GainNode
    @gain = @context.createGain()
    @gain.connect(@analyser)

  ############################################################################################################
  # Audio Processing   
  ############################################################################################################

  # AudioProcessingEvent Interface
  # This is an Event object which is dispatched to ScriptProcessorNode nodes. The event handler processes 
  # audio from the input (if any) by accessing the audio data from the inputBuffer attribute. The audio data 
  # which is the result of the processing (or the synthesized data if there are no inputs) is then placed into
  # the outputBuffer.
  # https://dvcs.w3.org/hg/audio/raw-file/tip/webaudio/specification.html#AudioProcessingEvent-section
  _setupAudioHandler: =>
    @scriptProcessor.onaudioprocess = (event) =>
      array = new Uint8Array(@analyser.frequencyBinCount)
      @analyser.getByteTimeDomainData(array)

      if @micRunning
        @_drawLiveWaveform(array) 

      if @isRecording
        @_drawRecording(array)
        leftChannel = event.inputBuffer.getChannelData(0)
        rightChannel = event.inputBuffer.getChannelData(0)

        # we clone the samples
        @track.leftChannel.push(new Float32Array(leftChannel))
        @track.rightChannel.push(new Float32Array(rightChannel))
        @track.length += @bufferSize;
     
  ############################################################################################################
  # Audio Utility (WAV Formatting)   
  ############################################################################################################

  _interleave: (leftChannel, rightChannel) =>
    length = leftChannel.length + rightChannel.length
    result = new Float32Array(length)
    inputIndex = 0
    index = 0

    while index < length
      result[index++] = leftChannel[inputIndex]
      result[index++] = rightChannel[inputIndex]
      inputIndex++
    result

  _mergeBuffers: (channelBuffer, recordingLength) =>
    result = new Float32Array(recordingLength)
    offset = 0
    lng = channelBuffer.length
    i = 0
    while i < lng
      buffer = channelBuffer[i]
      result.set buffer, offset
      offset += buffer.length
      i++
    result

  _writeUTFBytes: (view, offset, string) =>
    lng = string.length
    i = 0
    while i < lng
      view.setUint8 offset + i, string.charCodeAt(i)
      i++
    return

  ############################################################################################################
  # HTML5 Canvases   
  ############################################################################################################

  _setupCanvases: =>
    @width = @editor.find("#track").width()
    @height = @editor.find("#track").height()

    for id, element of @track['canvases']
      ctx = element[0].getContext("2d")
      ctx.canvas.width = @width
      ctx.canvas.height = @height
      ctx.save()

  _drawGrid: =>
    ctx = @track['canvases']['grid'][0].getContext("2d")
    for i in [0..@width]
      if (i%100 is 0 && i isnt 0 && i isnt @width)
        ctx.fillStyle = "#333333"
        ctx.fillRect(i, 0, 1, @height)

  _drawLiveWaveform: (array) =>
    ctx = @liveWaveform[0].getContext("2d")
    ctx.clearRect(0, 0, 100, 35)

    for i in [0..array.length]
      value = array[i]
      ctx.fillStyle = @chromaOrange(value / 255).hex()
      ctx.fillRect((i * 100) / 255, (value / 2) - 45, 1, 1)

  _drawWaveform: (array) =>
    ctx = @track['canvases']['wave'][0].getContext("2d")
    waveValues = []
    min = Math.min.apply(Math, array) * 400 / 255
    max = Math.max.apply(Math, array) * 400 / 255
    while min < max
      waveValues.push(min)
      min++

    for i in [0..waveValues.length]
      value = waveValues[i]
      ctx.fillStyle = @chromaOrange(value / 400).hex()
      ctx.fillRect(0, value, 1, 1)
    ctx.translate(1, 0)

  _drawCursor: =>
    console.log "track: ", @track
    ctx = @track['canvases']['cursor'][0].getContext("2d")
    ctx.fillStyle = "rgba(255,255,255,0.1)"
    ctx.fillRect(0, 0, 1, @height)
    ctx.translate(1, 0)
    console.log "cp: ", @cursorPosition
    @cursorPosition++

  _drawRecording: (array) =>
    @_drawWaveform(array)
    @_drawCursor()

  _resetTrack: =>
    # Reset Details
    @track.leftChannel.length = @track.rightChannel.length = @track.length = 0

    # Reset Track Canvas
    for id, element of @track['canvases']
      ctx = element[0].getContext("2d")
      ctx.save()
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      ctx.restore()

    # FIXME: Reset the Cursor
    # wave = @track['canvases']['wave'][0].getContext("2d")
    # wave.translate(-@currentPosition, 0);
    # wave.restore()

  ############################################################################################################
  # Event Handling
  ############################################################################################################
  
  _setupClickHandlers: =>
    # Start Microphone
    @editor.find("#mic-start").on 'click', (event) =>
      navigator.webkitGetUserMedia { audio: true }, (stream) =>
        @micSource = @context.createMediaStreamSource(stream)
        @micSource.connect(@gain)
        @micRunning = true
        $(".navbar .record").removeClass("disabled")

    # Stop Microphone
    @editor.find("#mic-stop").on 'click', (event) =>
      @micSource.disconnect(@volume)
      @micRunning = false
      $("#live-waveform").get()[0].getContext("2d").clearRect(0, 0, 100, 35)
      $(".navbar .record").addClass("disabled")

    # Start Recording
    @editor.find("#rec-start").on 'click', (event) =>
      if !$(this).closest("div.record").hasClass("disabled")
        $("div.record i").addClass("active")
        # Reset Track Canvas
        @_resetTrack()
        @_drawGrid()
        # Reset the buffers for the new recording
        @track.leftChannel.length = @track.rightChannel.length = 0
        @track.length = 0       
        @isRecording = true 

    # Stop Recording
    @editor.find("#rec-stop").on 'click', (event) =>
      $("div.record i").removeClass("active")
      @isRecording = false

      # First flatten the left and right channels down
      leftBuffer  = @_mergeBuffers(@track.leftChannel,  @track.length)
      rightBuffer = @_mergeBuffers(@track.rightChannel, @track.length)

      console.log "leftBuffer: ", leftBuffer
      console.log "rightBuffer: ", rightBuffer

      # Now interleave both channels together
      interleaved = @_interleave(leftBuffer, rightBuffer)

      console.log "interleaved: ", interleaved
    
      # Create a WAV file
      buffer = new ArrayBuffer(44 + interleaved.length * 2)
      view = new DataView(buffer)

      # RIFF chunk descriptor
      @_writeUTFBytes view, 0, "RIFF"
      view.setUint32 4, 44 + interleaved.length * 2, true
      @_writeUTFBytes view, 8, "WAVE"

      # FMT sub-chunk
      @_writeUTFBytes view, 12, "fmt "
      view.setUint32 16, 16, true
      view.setUint16 20, 1, true

      # stereo (2 channels)
      view.setUint16 22, 2, true
      view.setUint32 24, @sampleRate, true
      view.setUint32 28, @sampleRate * 4, true
      view.setUint16 32, 4, true
      view.setUint16 34, 16, true

      # data sub-chunk
      @_writeUTFBytes view, 36, "data"
      view.setUint32 40, interleaved.length * 2, true

      # write the PCM samples
      lng = interleaved.length
      index = 44
      volume = 1
      i = 0

      while i < lng
        view.setInt16 index, interleaved[i] * (0x7FFF * volume), true
        index += 2
        i++
      
      # our final binary blob
      @blob = new Blob([view], type: "audio/wav")
      @url = (window.URL || window.webkitURL).createObjectURL(@blob)

      console.log "Blob: ", @blob
      console.log "Url: ", @url

      link = window.document.createElement("a")
      link.href = @url
      link.download = 'output.wav'
      click = document.createEvent("Event")
      click.initEvent "click", true, true
      link.dispatchEvent click

##############################################################################################################
# On Ready   
##############################################################################################################
$(document).on 'ready', ->
  new Editor($('[data-editor]'));


