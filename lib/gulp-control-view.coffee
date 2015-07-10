crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
os = require 'os'

{BufferedProcess} = require 'atom'
{View} = require 'atom-space-pen-views'

Convert = require 'ansi-to-html'
convert = new Convert()

module.exports =
class GulpControlView extends View
  @content: ->
    @div class: 'gulp-control', =>
      @div class: 'sidebar', =>
        @div class: 'sidebarSection', =>
          @h6 "Gulpfiles:"
          @ul class: 'gulpfiles', outlet: 'gulpfilesList'
        @div class: 'sidebarSection', =>
          @h6 "Tasks:"
          @ul class: 'tasks', outlet: 'taskList'
      @div class: 'output', outlet: 'outputPane'

  serialize: ->

  initialize: ->
    console.log 'GulpControlView: initialize'

    projpaths = atom.project.getPaths()
    if !projpaths or !projpaths.length or !projpaths[0]
      @writeOutput 'No project path found, aborting', 'error'
      return

    @click '.gulpfiles li.item', (event) =>
      targetFilePath = event.target.textContent
      for gulpfile in @gulpfiles
        filePath = @createFilePath(gulpfile.dir, gulpfile.fileName)
        if filePath == targetFilePath
          @find(".gulpfiles .item").removeClass("active unning")
          @find(event.target).addClass("active running")
          @gulpFilePath = targetFilePath
          @getGulpTasks()


    @click '.tasks li.item', (event) =>
      task = event.target.textContent
      for t in @tasks when t is task
        return @runGulp(task)

    @initializeGulpFileList()

    @getGulpTasks()

    return

  initializeGulpFileList: ->
    projPath = atom.project.getPaths()[0]
    @gulpfiles = @getGulpfiles(projPath)

    if not @gulpfiles or not @gulpfiles.length
      @writeOutput "Unable to find any gulpfiles
        in #{projPath}/**/gulpfile.[js|coffee]", 'error'
      return

    @gulpFilePath = @createFilePath(@gulpfiles[0].dir, @gulpfiles[0].fileName)

    for gulpfile in @gulpfiles
      filePath = @createFilePath(gulpfile.dir, gulpfile.fileName)

      if @gulpFilePath == filePath
        @gulpfilesList.append "<li class='active running item'>#{filePath}</li>"
      else
        @gulpfilesList.append "<li class='item'>#{filePath}</li>"

    return

  destroy: ->
    console.log 'GulpControlView: destroy'

    if @process
      @process.kill()
      @process = null
    @detach()
    return

  getTitle: ->
    return 'gulp.js:control'

  createFilePath: (dir, fileName) ->
    isWin = /^win/.test(process.platform)
    if isWin
      return dir + '\\' + fileName
    else
      return dir + '/' + fileName

  getGulpfiles: (cwd, gulpfiles) ->
    dirs = []
    if not gulpfiles
      gulpfiles = []

    gfregx = /^gulpfile\.[js|coffee]/i
    for entry in fs.readdirSync(cwd) when entry.indexOf('.') isnt 0
      if gfregx.test(entry)
        gulpfiles.push({
          dir: cwd,
          fileName: entry
        })

      else if entry.indexOf('node_modules') is -1
        abs = path.join(cwd, entry)
        if fs.statSync(abs).isDirectory()
          dirs.push abs

    for dir in dirs
      if foundGulpfiles = @getGulpfiles(dir)
        gulpfiles = gulpfiles.concat(foundGulpfiles)

    return gulpfiles

  getTaskId: (taskname) ->
    shasum = crypto.createHash('sha1')
    shasum.update(taskname)
    return "gulp-#{shasum.digest('hex')}"


  getGulpTasks: ->
    @writeOutput "Using #{@gulpFilePath}"
    @writeOutput 'Retrieving list of gulp tasks'

    @tasks = []

    onOutput = (output) =>
      for task in output.split('\n') when task.length
        @tasks.push task


    onError = (output) =>
      @gulpErr(output)

    onExit = (code) =>
      if code is 0
        @taskList.empty()
        for task in @tasks.sort()
          tid = @getTaskId(task)
          @taskList.append "<li id='#{tid}' class='item'>#{task}</li>"
        @writeOutput "#{@tasks.length} tasks found"

      else
        @gulpExit(code)
        console.error 'GulpControl: getGulpTasks, exit', code

    @runGulp '--tasks-simple', onOutput, onError, onExit

    return

  runGulp: (task, stdout, stderr, exit) ->
    if @process
      @process.kill()
      @process = null

    command = 'gulp'
    # if gulp is installed localy, use that instead
    projpath = atom.project.getPaths()[0]
    localGulpPath = path.join(projpath, 'node_modules', '.bin', 'gulp')
    if fs.existsSync(localGulpPath)
      command = localGulpPath

    args = [task, '--color', '--gulpfile', @gulpFilePath]

    process.env.PATH = switch process.platform
      when 'win32' then process.env.PATH
      else "#{process.env.PATH}:/usr/local/bin"

    options =
      env: process.env

    stdout or= (output) => @gulpOut(output)
    stderr or= (code) => @gulpErr(code)
    exit or= (code) => @gulpExit(code)

    if task.indexOf('-')
      @writeOutput '&nbsp;'
      @writeOutput "Running gulp #{task}"

    tid = @getTaskId(task)

    @find('.tasks li.item.active').removeClass 'active'
    @find(".tasks li.item##{tid}").addClass 'active running'

    @process = new BufferedProcess({command, args, options, stdout, stderr, exit})
    return

  writeOutput: (line, klass) ->
    if line and line.length
      @outputPane.append "<pre class='#{klass or ''}'>#{line}</pre>"
      @outputPane.scrollToBottom()
    return

  gulpOut: (output) ->
    for line in output.split('\n')
      @writeOutput convert.toHtml(line)
    return

  gulpErr: (output) ->
    for line in output.split('\n')
      @writeOutput convert.toHtml(line), 'error'
    return

  gulpExit: (code) ->
    @find('.tasks li.task.active.running').removeClass 'running'
    @writeOutput "Exited with code #{code}", "#{if code then 'error' else ''}"
    @process = null
    return
