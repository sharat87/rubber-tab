$ng = angular
$ng.module \rubber-app, <[ngAnimate]>

.run ->
  # Transition from the old way of saving bars to the new serialization method.
  return unless localStorage.bars and not localStorage.lastId
  bars = $ng.fromJson localStorage.bars
  localStorage.lastId = 0
  if $ng.isString bars[0]
    bars = [{name, id: localStorage.lastId++} for name in bars]
    localStorage.bars = $ng.toJson bars

.config ($compileProvider) ->
  $compileProvider.imgSrcSanitizationWhitelist /^(https?|chrome):/
  $compileProvider.aHrefSanitizationWhitelist /^(https?|chrome(-extension)?):/

.directive \href, ->
  (scope, element, attrs) ->
    if attrs.href is \newtab
      element.on \click, (e) ->
        alert 'Opening to the native new tab cannot currently be done. Please ' +
          'see this chrome bug for more details: ' +
          'https://code.google.com/p/chromium/issues/detail?id=336304'
        e.prevent-default!
    else if attrs.href.match /^chrome:/
      element.on \click, -> chrome.tabs.update url: attrs.href

.directive \cleanTextNodes, ->
  # Removes text nodes that only contain whitespace, recursively. This is
  # currently used in the nav button-bars to remove the small text-like spacing
  # that appears between the buttons, because of the newlines and indentation in
  # the html source.

  clean = (el) !->
    for child in Array.prototype.slice.call(el.child-nodes, 0)
      if child.node-type is Node.TEXT_NODE and not /\S/.test(child.node-value)
        child.remove!
      else if child.node-type is Node.ELEMENT_NODE
        clean child

  (scope, element, attrs) !->
    clean element[0]

.factory \store, ->
  # A caching/storage abstraction, based on localStorage
  (scope, ns, defaults) ->
    if arguments.length is 2
      defaults = ns
      # If no `ns` is given, the caller is assumed to be a bar and as such, a
      # `bar` object is assumed to be present on the scope. This will be the
      # case, as long as it is indeed the scope of a bar controller handled by
      # AppCtrl in the bar lising `ng-repeat` directive.
      ns = "store:#{scope.bar.id}:#{scope.bar.name}"

    $ng.extend scope, defaults, $ng.fromJson(localStorage[ns])

    build = ->
      cacheObj = {}
      for key of defaults
        cacheObj[key] = scope[key]
      cacheObj

    save = (cacheObj) ->
      localStorage[ns] = $ng.toJson cacheObj

    clear = ->
      delete localStorage[ns]

    scope.$watch build, save, yes
    scope.$on \$destroy, clear

.value \registry,
  # Registry holds bar types available and some metadata about them.
  datetime:
    title: 'Date and Time'
    icon: \clock
  gmail:
    title: 'GMail'
    icon: \mail
  facebook:
    title: 'Facebook'
    icon: \facebook
  weather:
    title: 'Weather'
    icon: \weather
  news:
    title: 'Google News'
    icon: \news
  rss:
    title: 'RSS Ticker'
    icon: \rss
  topsites:
    title: 'Top Sites'
    icon: \history
  reddit:
    title: 'Reddit Inbox'
    icon: \reddit
  subreddit:
    title: 'Sub-reddit'
    icon: \reddit
  feedly:
    title: 'Feedly counts'
    # Icon taken from https://en.wikipedia.org/wiki/File:Feedly_Logo.svg
    icon: \feedly_logo

.controller \AppCtrl, ($scope, $window, store, registry) ->
  store $scope, \options,
    fontFamily: ''
    theme: \black-beauty

  $scope.nav = $window.navigator
  $scope.registry = registry

  $scope.addNewBar = (name) ->
    localStorage.lastId or= 0
    $scope.bars.push {name, id: ++localStorage.lastId}

  $scope.removeBar = (bar) ->
    $scope.bars.splice $scope.bars.indexOf(bar), 1

  $scope.bars = $ng.fromJson localStorage.bars

  unless $scope.bars
    # If there are no saved bars, like when just installed, create a default set.
    $scope.bars = []
    for name in <[datetime gmail facebook weather topsites news]>
      $scope.addNewBar name

  $scope.$watchCollection \bars, -> localStorage.bars = $ng.toJson $scope.bars

  $scope.moveUp = (bar) ->
    index = $scope.bars.indexOf bar
    tmp = $scope.bars[index]
    $scope.bars[index] = $scope.bars[index - 1]
    $scope.bars[index - 1] = tmp

  $scope.moveDown = (bar) ->
    index = $scope.bars.indexOf bar
    tmp = $scope.bars[index]
    $scope.bars[index] = $scope.bars[index + 1]
    $scope.bars[index + 1] = tmp

  $scope.reset = ->
    if confirm 'This will erase all your rubber-tab configuration and restores the defaults.\n\nSure?'
      localStorage.clear()
      $window.location.reload()

.factory \placeQ, ($http, $q, $window) ->
  defer = $q.defer()

  $window.navigator.geolocation.getCurrentPosition (pos) ->
    query = "select * from geo.placefinder where text='#{pos.coords.latitude} #{pos.coords.longitude}' and gflags='R' and focus='' limit 1"
    $http(
      method: \GET
      url: 'https://query.yahooapis.com/v1/public/yql'
      params:
        format: \json
        q: query
      transformResponse: (data) ->
        data = $ng.fromJson data
        if data?.query.count then data.query.results.Result
    ).success((data) ->
      # console.log 'place data:', data
      defer.resolve data
    ).error (err) ->
      console.log 'place error:', err
      defer.reject err

  defer.promise

.controller \BookmarkBar, ($scope, $interval) ->
  chrome.bookmarks.getTree (tree) ->
    other = tree[0].children[1]
    mobile = tree[0].children[2]
    $scope.bar = tree[0].children[0]
    do $scope.$digest

.controller \TimeBar, ($scope, $interval, store) ->
  store $scope,
    use24: no

  updateTime = ->
    d = new Date()
    date = d.getDate()
    minutes = d.getMinutes()
    hours = d.getHours()

    suffix = \th
    if date in [1, 21, 31]
      suffix = \st
    else if date in [2, 22]
      suffix = \nd
    else if date in [3, 23]
      suffix = \rd

    $ng.extend $scope,
      hour12: (hours + 11) % 12 + 1
      hour24: hours
      minute: ((if minutes > 9 then '' else '0')) + minutes
      isAm: hours < 12
      weekday: weekdays[d.getDay()]
      date: date
      dateSuffix: suffix
      month: months[d.getMonth()]
      year: d.getFullYear()

  weekdays = <[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]>
  months = <[January February March April May June July August September October
                November December]>

  do updateTime
  $interval updateTime, 1000

.controller \GMailBar, ($scope, $http, store) ->
  store $scope,
    unreads: null

  $http(
    method: \GET
    url: 'https://mail.google.com/mail/feed/atom'
    transformResponse: (data) ->
      new DOMParser().parseFromString data, \text/xml
  ).success((response) ->
    $scope.unreads = response.getElementsByTagName(\fullcount)[0].textContent
  ).error (err) ->
    console.log 'gmail failure:', err

.controller \FacebookBar, ($scope, $http, store) ->
  store $scope,
    inbox: null
    notifications: null

  $http.get(\https://www.facebook.com/desktop_notifications/counts.php).success((data) ->
    # console.log 'facebook response:', data
    $scope.inbox = data.inbox
    $scope.notifications = data.notifications
  ).error (err) ->
    console.log 'facebook failure:', err

.controller \WeatherBar, ($scope, $http, placeQ, store) ->
  # Thanks to HumbleNewTabPage for help with this.
  # Weather API: http://developer.yahoo.com/weather/

  store $scope,
    temperature: null
    condition: null
    address: ''
    location: {}
    units: \c
    hideLocation: no

  loadWeather = (woeid, address='') ->
    query = "select * from weather.forecast where woeid='#{woeid}' and u='c' limit 1"
    $http do
      method: \GET
      url: \https://query.yahooapis.com/v1/public/yql
      params:
        format: \json
        q: query
      transformResponse: (data) ->
        data = JSON.parse data
        if data?.query.count then data.query.results.channel
    .success (data) ->
      $ng.extend $scope,
        temperature: parseInt data.item.condition.temp, 10
        condition: data.item.condition.text
        location:
          address: address
          city: data.location.city
          country: data.location.country
          woeid: woeid
    .error (data) ->
      console.log 'weather error:', data

  if $scope.address

    if $scope.address is $scope.location.address
      loadWeather $scope.location.woeid, $scope.address

    else
      $scope.temperature = null
      query = "select * from geo.placefinder where text='#{$scope.address}' and gflags='R' and focus='' limit 1"
      $http do
        method: \GET
        url: 'https://query.yahooapis.com/v1/public/yql'
        params:
          format: \json
          q: query
        transformResponse: (data) ->
          data = JSON.parse(data)
          if data?.query.count then data.query.results.Result
      .success (data) ->
        console.log 'place data:', data
        loadWeather data.woeid, $scope.address
      .error (err) ->
        $scope.location = null
        console.log 'place error:', err

  else
    if $scope.location.address
      $scope.temperature = null

    placeQ.then (place) -> loadWeather place.woeid

.controller \NewsBar, ($scope, $http, $interval, placeQ, store) ->
  store $scope,
    items: null
    edition: null
    lang: \en
    topic: \w

  loadNews = ->
    $http do
      method: \GET
      url: \https://news.google.com/news/feeds
      params:
        # cf: \all
        ned: $scope.edition
        # region: \in
        topic: $scope.topic
        hl: $scope.lang
        output: \rss
      transformResponse: (data) ->
        new DOMParser().parseFromString data, \text/xml
    .success(updateNews).error (err) ->
      console.log 'news error:', err

  updateNews = (news) ->
    $scope.items = for el in news.getElementsByTagName \item
      title: el.getElementsByTagName(\title)[0].textContent.trim()
      link: el.getElementsByTagName(\link)[0].textContent.trim()

  if $scope.edition
    do loadNews
  else
    placeQ.then (place) ->
      $scope.edition = place.countrycode.toLowerCase()
      do loadNews

.controller \RssBar, ($scope, $http, $interval, $timeout, placeQ, store) ->
  store $scope,
    items: null
    feedUrl: null

  $scope.setup = ->
    $scope.feedUrl = $scope.newFeedUrl

  updateNews = (news) ->
    $scope.items = for el in news.getElementsByTagName \item
      title: el.getElementsByTagName(\title)[0].textContent.trim()
      link: el.getElementsByTagName(\link)[0].textContent.trim()

  loadFeed = (url=$scope.feedUrl) ->
    $http do
      method: \GET
      url: if url.indexOf(\://) > 0 then url else "http://#{url}"
      transformResponse: (data) ->
        new DOMParser().parseFromString data, \text/xml
    .success(updateNews).error (err) ->
      console.log 'rss error:', url, err

  var time
  $scope.$watch \feedUrl, (value) ->
    return unless value
    time := Date.now!
    $timeout ((t) -> (-> do loadFeed if t is time))(time), 800

.controller \TopSitesBar, ($scope, $interval, store) ->
  store $scope,
    showFavicons: yes

  chrome.topSites.get (items) -> $scope.items = items

.controller \RedditBar, ($scope, $http, store) ->
  store $scope,
    unreads: null

  $http do
    method: \GET
    url: 'http://reddit.com/message/unread.json?mark=false&app=rtab'
  .success (response) ->
    # console.log 'reddit success', response
    $scope.unreads = response.data.children.length
  .error (err) ->
    console.log 'reddit failure:', err

.controller \SubRedditBar, ($scope, $http, $interval, $timeout, placeQ, store) ->
  store $scope,
    items: null
    subr: null

  $scope.setup = ->
    $scope.subr = $scope.newSubr

  load = ->
    $http do
      method: \GET
      url: "http://www.reddit.com/r/#{$scope.subr}.json"
      transformResponse: (data) -> $ng.fromJson(data).data.children
    .success (news) ->
      $scope.items = for item in news
        title: item.data.title
        url: item.data.url
        comments:
          url: 'http://reddit.com' + item.data.permalink
          count: item.data.num_comments
    .error (err) ->
      console.log 'subreddit error:', $scope.subr, err

  var time
  $scope.$watch \subr, (value) ->
    return unless value
    time := Date.now!
    $timeout ((t) -> (-> do load if t is time))(time), 800

.controller \FeedlyBar, ($scope, $http, store) ->
  store $scope,
    unreads: null

  chrome.cookies.get {url: 'https://feedly.com', name: \session@cloud}, (cookie) ->
    if not cookie
      console.error 'Cannot find feedly token cookie'

    token = $ng.fromJson(cookie.value).feedlyToken

    $http do
      method: \GET
      url: 'https://feedly.com/v3/markers/counts'
      headers: {Authorization: token}
      transformResponse: (data) -> $ng.fromJson(data).unreadcounts
    .success (counts) ->
      for cnt in counts
        if cnt.id.match /\/global\.all$/
          $scope.unreads = cnt.count
          break
    .error (err) ->
      console.log 'feedly error:', err

.controller \AppsListCtrl, ($scope, $timeout, $window, $location) ->
  knownApps = $ng.fromJson(localStorage.knownApps) or []

  build = (app) ->
    if app.type in <[extension theme]>
      return null

    if not app.enabled and app.disabledReason is \permissions_increase
      app.permInc = yes

    else unless app.enabled
      return null

    app.largestIcon = app.icons[0]
    for icon in app.icons
      if icon.size is 48
        app.largestIcon = icon
        break
      else if icon.size > app.largestIcon.size
        app.largestIcon = icon

    if app.isDev = app.installType is \development
      app.name += ' (Dev)'

    unless app.enabled
      app.name += ' (Disabled)'

    app.manageUrl = "chrome://extensions/?id=#{app.id}"

  chrome.management.getAll (allExts) ->

    apps = for app in allExts
      app if build app

    $scope.$apply ->
      $scope.apps = apps

    $timeout ->
      knownApps := for app in $scope.apps
        if knownApps.length > 0 and app.id not in knownApps
          app.isNew = yes
        app.id
      localStorage.knownApps = $ng.toJson knownApps

  chrome.management.onInstalled.addListener (app) ->
    return unless build app
    $scope.$apply ->
      $scope.apps.push app
      $timeout -> app.isNew = yes

  $scope.uninstall = (app) ->
    # TODO: Animate the disappearance of the app icon.
    chrome.management.uninstall app.id, {showConfirmDialog: yes}, ->
      unless chrome.extension.lastError
        $scope.apps.splice $scope.apps.indexOf(app), 1

  $scope.launch = (app, e) ->
    e.preventDefault!
    if app.appLaunchUrl
      chrome.tabs.update null, url: app.appLaunchUrl
    else
      chrome.management.launchApp app.id, -> do $window.close

  $scope.$watch \apps.length, (len) ->
    return unless len?
    localStorage.knownApps = $ng.toJson [app.id for app in $scope.apps]

.controller \BookmarksCtrl, ($scope) ->

  chrome.bookmarks.getTree (tree) ->
    tree = tree[0].children
    $scope.currentTree = tree[0]
    $scope.currentTree.children.push tree[1]
    $scope.currentTree.children.push tree[2]
    $scope.stack = []

  $scope.openMark = (item, event) ->
    unless item.url
      $scope.stack.push $scope.currentTree
      $scope.currentTree = item
      event.stopPropagation!

  $scope.openBack = (event) ->
    $scope.currentTree = $scope.stack.pop!
    event.stopPropagation!

.directive \tip, ->

  restrict: \A
  link: (scope, element, attrs) ->
    tip = document.createElement \div
    tip.className = \tip
    document.body.appendChild tip

    element.on \mouseenter, ->
      tip.style.display = \block
      elRect = element[0].getBoundingClientRect!
      tipRect = tip.getBoundingClientRect!
      $ng.extend tip.style,
        top: (elRect.top - tipRect.height - 1) + 'px'
        left: elRect.left + 'px'

    element.on \mouseleave, ->
      tip.style.display = ''

    attrs.$observe \tip, (value) ->
      tip.innerText = value

.directive \menuBox, ($document) ->
  openedMenu = null

  close = ->
    return unless openedMenu
    openedMenu.classList.remove \menu-open
    for child in openedMenu.children
      child.classList.remove \active
    openedMenu := null

  open = (element) ->
    do close
    (openedMenu := element).classList.add \menu-open
    for child in element.children
      child.classList.add \active

  $document.on(\click, close).on \keydown, (e) ->
    do close if e.which is 27 # ESC

  (scope, element, attrs) ->
    element = element[0]
    evt = attrs.menuBox or \click

    handler = (e) ->
      # TODO: Determine the best position for the menu to open and add the
      # appropriate class(es).
      if evt is \contextmenu
        return if e.shiftKey
        do e.preventDefault
      else
        do e.stopPropagation
      open element

    for child in element.children
      if child.tagName is \A
        child.addEventListener evt, handler

.directive \tick, ($interval) ->
  # Value of the ticker attribute, if any is the delay between each tick (in
  # ms). Defaults to 9000.
  restrict: \A
  link: (scope, element, attrs) ->
    tickerEl = element[0]
    hide = (el) -> el.style.display = \none
    show = (el) -> el.style.display = ''

    # Find out the iterable over which the ngRepeat is working with.
    for child in tickerEl.childNodes
      if child.nodeType is 8 and child.nodeValue.indexOf(\ngRepeat) >= 0 # Comment node
        iterable = child.nodeValue.match(/ngRepeat: .+? in (.+?) /)[1]
        break

    var intervalPromise, isExpanded
    current = -1

    scope.$watch iterable, ->
      if intervalPromise
        $interval.cancel intervalPromise

      return unless scope[iterable]?.length

      for child in tickerEl.children
        hide child

      tick = ->
        return if isExpanded
        if current >= 0
          hide tickerEl.children[current]
        current := 0 if ++current is tickerEl.children.length
        show tickerEl.children[current]

      do tick
      intervalPromise := $interval tick, (attrs.tick or 9000)

    scope.$watch \expanded, (val) !->
      tickerEl.classList[if isExpanded := val then \add else \remove] \expanded
      for child in tickerEl.children
        if val or child is tickerEl.children[current]
          show child
        else
          hide child

.directive \leftBtns, (registry) ->
  restrict: \E
  templateUrl: \left-btns.html
  replace: yes
  scope: iref: \@
  link: (scope, element, attrs) ->
    scope.icon = registry[scope.$parent.bar.name].icon
    scope.moveUp = -> scope.$parent.moveUp scope.$parent.bar
    scope.moveDown = -> scope.$parent.moveDown scope.$parent.bar

.directive \rightBtns, ->
  restrict: \E
  templateUrl: \right-btns.html
  replace: yes
  scope: configurable: \@ expandable: \@
  link: (scope, element, attrs) ->
    scope.remove = ->
      scope.$parent.removeBar scope.$parent.bar

    scope.togglePrefs = ->
      scope.$parent.showPrefs = not scope.$parent.showPrefs

    scope.toggleExpand = ->
      scope.$parent.expanded = not scope.$parent.expanded

.directive \btns, ->
  # Remove all immediate children that are text nodes. This is used on icon
  # buttons in the bar where the newline used in the html markup is coming up as
  # a small gap between the buttons. The only solution I found is to remove
  # these text nodes manually.

  clean = (el) ->
    for child in el.childNodes
      if child?.nodeType is 3
        el.removeChild child
    for child in el.children
      clean child

  restrict: 'C'
  link: (scope, element, attrs) -> clean element[0]
