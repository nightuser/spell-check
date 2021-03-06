_ = require 'underscore-plus'
{CompositeDisposable} = require 'atom'
SpellCheckTask = require './spell-check-task'

CorrectionsView = null
SpellChecker = null

module.exports =
class SpellCheckView
  @content: ->
    @div class: 'spell-check'

  constructor: (@editor) ->
    @disposables = new CompositeDisposable
    @task = new SpellCheckTask()
    @initializeMarkerLayer()

    @correctMisspellingCommand = atom.commands.add atom.views.getView(@editor), 'spell-check:correct-misspelling', =>
      if marker = @markerLayer.findMarkers({containsBufferPosition: @editor.getCursorBufferPosition()})[0]
        CorrectionsView ?= require './corrections-view'
        @correctionsView?.destroy()
        @correctionsView = new CorrectionsView(@editor, @getCorrections(marker), marker)

    @task.onDidSpellCheck (misspellings) =>
      @detroyMarkers()
      @addMarkers(misspellings) if @buffer?

    @disposables.add @editor.onDidChangePath =>
      @subscribeToBuffer()

    @disposables.add @editor.onDidChangeGrammar =>
      @subscribeToBuffer()

    @disposables.add atom.config.onDidChange 'editor.fontSize', =>
      @subscribeToBuffer()

    @disposables.add atom.config.onDidChange 'spell-check.grammars', =>
      @subscribeToBuffer()

    @subscribeToBuffer()

    @disposables.add @editor.onDidDestroy(@destroy.bind(this))

  initializeMarkerLayer: ->
    @markerLayer = @editor.addMarkerLayer({maintainHistory: false})
    @markerLayerDecoration = @editor.decorateMarkerLayer(@markerLayer, {
      type: 'highlight',
      class: 'spell-check-misspelling',
      deprecatedRegionClass: 'misspelling'
    })

  destroy: ->
    @unsubscribeFromBuffer()
    @disposables.dispose()
    @task.terminate()
    @markerLayer.destroy()
    @markerLayerDecoration.destroy()
    @correctMisspellingCommand.dispose()
    @correctionsView?.remove()

  unsubscribeFromBuffer: ->
    @detroyMarkers()

    if @buffer?
      @bufferDisposable.dispose()
      @buffer = null

  subscribeToBuffer: ->
    @unsubscribeFromBuffer()

    if @spellCheckCurrentGrammar()
      @buffer = @editor.getBuffer()
      @bufferDisposable = @buffer.onDidStopChanging => @updateMisspellings()
      @updateMisspellings()

  spellCheckCurrentGrammar: ->
    grammar = @editor.getGrammar().scopeName
    _.contains(atom.config.get('spell-check.grammars'), grammar)

  detroyMarkers: ->
    @markerLayer.destroy()
    @markerLayerDecoration.destroy()
    @initializeMarkerLayer()

  addMarkers: (misspellings) ->
    for misspelling in misspellings
      @markerLayer.markBufferRange(misspelling, {invalidate: 'touch'})

  updateMisspellings: ->
    # Task::start can throw errors atom/atom#3326
    try
      @task.start(@buffer.getText())
    catch error
      console.warn('Error starting spell check task', error.stack ? error)

  getCorrections: (marker) ->
    if SpellChecker == null
      SpellChecker = require 'spellchecker'
      SpellChecker.add("GitHub")
      SpellChecker.add("github")
      dicts = atom.config.get('spell-check.dicts')
      dictsDir = atom.config.get('spell-check.dictsDir')
      for dict in dicts
        SpellChecker.addDictionary(dict, dictsDir)
    misspelling = @editor.getTextInBufferRange(marker.getBufferRange())
    corrections = SpellChecker.getCorrectionsForMisspelling(misspelling)
