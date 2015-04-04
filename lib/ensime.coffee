net = require('net')
exec = require('child_process').exec
fs = require 'fs'
{Subscriber} = require 'emissary'
SwankClient = require './swank-client'
StatusbarView = require './statusbar-view'
{CompositeDisposable} = require 'atom'
{car, cdr, fromLisp} = require './lisp'
{sexpToJObject} = require './swank-extras'

portFile = ->
    loadSettings = atom.getLoadSettings()
    console.log('loadSettings: ' + loadSettings)
    projectPath = atom.project.getPath()
    console.log('project path: ' + projectPath)
    projectPath + '/.ensime_cache/port'


readDotEnsime = -> # TODO: error handling
  raw = fs.readFileSync(atom.project.getPath() + '/.ensime')
  rows = raw.toString().split(/\r?\n/);
  filtered = rows.filter (l) -> l.indexOf(';;') != 0
  filtered.join('\n')

createSwankClient = (portFileLoc, generalHandler) ->
  console.log("portFileLoc: " + portFileLoc)
  port = fs.readFileSync(portFileLoc)
  new SwankClient(port, generalHandler)

startEnsime = (portFile) ->
  ensimeLocation = '~/dev/projects/ensime-src/dist'
  #ensimeServerBin = ensimeLocation + '/2.10/bin/server'
  ensimeServerBin = ensimeLocation + '/2.11/bin/server'
  command = 'cd ' + ensimeLocation + '\n' + ensimeServerBin + ' ' + portFile
  console.log("Running command: " + command)
  child = exec(command, (error, stdout, stderr) ->
    console.log('stdout: ' + stdout);
    console.log('stderr: ' + stderr);
    if(error != null)
      console.log('exec error: ' + error);
  )



module.exports = Ensime =
  subscriptions: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @statusbarView = new StatusbarView()
    @statusbarView.init()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'ascii-art:convert': => @convert()

    # Need to have a started server and port file
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:init-project", => @initProject()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:start-server", => @startEnsime()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-all", => @typecheckAll()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:init-builder", => @initBuilder()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:go-to-definition", => @goToDefinition()


  deactivate: ->
    @subscriptions.dispose()

  serialize: ->

  generalHandler: (msg) ->
    head = car(msg)
    tail = cdr(msg)
    headStr = head.toString()
    console.log("this: " + this)

    if(headStr == ':compiler-ready')
      @statusbarView.setText('compiler ready…')

    else if(headStr == ':full-typecheck-finished')
      @statusbarView.setText('Full typecheck finished!')

    else if(headStr == ':indexer-ready')
      @statusbarView.setText('indexer ready…')

    else if(headStr == ':clear-all-java-notes')
      @statusbarView.setText('feature todo: clear all java notes')

    else if(headStr == ':clear-all-scala-notes')
      @statusbarView.setText('feature todo: clear all scala notes')

    else if(headStr.startsWith(':background-message'))
      @statusbarView.setText("#{tail}")

    else if(headStr == ':scala-notes')
      @handleScalaNotes(tail)


  _client: null
  client: ->
    that = this
    if(@_client) then @_client else
      @_client = createSwankClient(portFile(), (msg) -> that.generalHandler(msg) )
      @_client

  startEnsime: ->
    startEnsime(portFile())

  initProject: ->
    @client().sendAndThen("(swank:init-project)", (msg) -> )

  typecheckAll: ->
    @client().sendAndThen("(swank:typecheck-all)", (msg) ->)

  initBuilder: ->
    #client.write(swankRpc("(swank:builder-init)"))

  goToDefinition: ->
    editor = atom.workspace.getActiveTextEditor()
    textBuffer = editor.getBuffer()
    pos = editor.getCursorBufferPosition()
    offset = textBuffer.characterIndexForPosition(pos)
    file = textBuffer.getPath()
    @client().sendAndThen("(swank:type-at-point \"#{file}\" #{offset})", (msg) ->
      # (:return (:ok (:arrow-type nil :name "Ingredient" :type-id 3 :decl-as class :full-name "se.kostbevakningen.model.record.Ingredient" :type-args nil :members nil :pos (:type offset :file "/Users/viktor/dev/projects/kostbevakningen/src/main/scala/se/kostbevakningen/model/record/Ingredient.scala" :offset 545) :outer-type-id nil)) 3)
      pos = msg[":ok"]?[":pos"]
      targetFile = pos[":file"]
      targetOffset = pos[":offset"]
      console.log("targetFile: #{targetFile}")
      atom.workspace.open(targetFile).then (editor) ->
        targetEditorPos = editor.getBuffer().positionForCharacterIndex(parseInt(targetOffset))
        editor.setCursorScreenPosition(targetEditorPos)
    )

  handleScalaNotes: (msg) ->
    parsed = sexpToJObject msg
    console.log("parsed notes: " + parsed)
    parsed