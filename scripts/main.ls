$ng = angular
app = $ng.module \app, <[ngAnimate]>

app.config ($compileProvider) ->
  $compileProvider.imgSrcSanitizationWhitelist /^(https?|chrome):/
  $compileProvider.aHrefSanitizationWhitelist /^(https?|chrome-extension):/

app.directive \href, ->
  # Fix anchor tags that link to chrome internal pages. Chrome stops them from
  # working for security reasons.
  (scope, element, attrs) ->
    if attrs.href.match /^chrome(-internal)?:/
      element.on \click, -> chrome.tabs.update url: attrs.href

app.factory \store, ->
  # A caching abstraction, based on localStorage
  (scope, defaults) ->
    # The `bar` object is assumed to be present on the scope. It will be
    # present, as long as its the scope of a bar controller handled by AppCtrl
    # in the bar lising `ng-repeat` directive.
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

app.value \registry,
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
  topsites:
    title: 'Top Sites'
    icon: \history

app.controller \AppCtrl, ($scope, $window, registry) ->
  $scope.nav = $window.navigator
  $scope.registry = registry

  $scope.addNewBar = (name) ->
    localStorage.lastId or= 0
    $scope.bars.push {name, id: ++localStorage.lastId}

  $scope.removeBar = (bar) ->
    $scope.bars.splice $scope.bars.indexOf(bar), 1

  $scope.bars = $ng.fromJson localStorage.bars

  unless $scope.bars
    # If there are no saved bars, add one of each bar type.
    $scope.bars = []
    for name of registry
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

app.factory \placeQ, ($http, $q, $window) ->
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
        data = JSON.parse(data)
        if data?.query.count then data.query.results.Result
    ).success((data) ->
      # console.log 'place data:', data
      defer.resolve data
    ).error (err) ->
      console.log 'place error:', err
      defer.reject err

  defer.promise

app.controller \BookmarkBar, ($scope, $interval) ->
  chrome.bookmarks.getTree (tree) ->
    other = tree[0].children[1]
    mobile = tree[0].children[2]
    $scope.bar = tree[0].children[0]
    do $scope.$digest

app.controller \TimeBar, ($scope, $interval, store) ->
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

app.controller \GMailBar, ($scope, $http, store) ->
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

app.controller \FacebookBar, ($scope, $http, store) ->
  store $scope,
    inbox: null
    notifications: null

  $http.get(\https://www.facebook.com/desktop_notifications/counts.php).success((data) ->
    # console.log 'facebook response:', data
    $scope.inbox = data.inbox
    $scope.notifications = data.notifications
  ).error (err) ->
    console.log 'facebook failure:', err

app.controller \WeatherBar, ($scope, $http, placeQ, store) ->
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

app.controller \NewsBar, ($scope, $http, $interval, placeQ, store) ->
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

    $scope.activeIndex = 0
    $scope.activeItem = $scope.items[$scope.activeIndex]

  tickNews = ->
    return if $scope.expanded or not $scope.items
    $scope.activeIndex = ($scope.activeIndex + 1) % $scope.items.length
    $scope.activeItem = $scope.items[$scope.activeIndex]

  $scope.toggleExpand = ->
    $scope.expanded = not $scope.expanded

  if $scope.edition
    do loadNews
  else
    placeQ.then (place) ->
      $scope.edition = place.countrycode.toLowerCase()
      do loadNews

  do tickNews
  $interval tickNews, 9000

app.controller \TopSitesBar, ($scope, $interval, store) ->
  store $scope,
    showFavicons: yes

  chrome.topSites.get (items) -> console.log($scope.items = items)

  # FIXME: Code repetition, copied from news widget.
  $scope.activeIndex = 0
  tick = ->
    return if $scope.expanded or not $scope.items
    $scope.activeIndex = ($scope.activeIndex + 1) % $scope.items.length

  $scope.toggleExpand = ->
    $scope.expanded = not $scope.expanded

  do tick
  $interval tick, 4000

app.controller \AppsListCtrl, ($scope) ->
  chrome.management.getAll (allExts) ->

    apps = for ext in allExts
      continue if not ext.enabled or ext.type is \extension or ext.type is \theme
      ext.largestIcon = ext.icons[0]

      for icon in ext.icons
        if icon.size is 48
          ext.largestIcon = icon
          break
        else if icon.size > ext.largestIcon.size
          ext.largestIcon = icon

      ext

    $scope.$apply ->
      $scope.apps = apps

  $scope.uninstall = (app) ->
    # TODO: Animate the disappearance of the app icon.
    chrome.management.uninstall app.id, {showConfirmDialog: yes}, ->
      unless chrome.extension.lastError
        $scope.apps.splice $scope.apps.indexOf(app), 1

app.directive \tooltip, ->
  (scope, element, attrs) ->
    element.after $ng.element(\<div>).addClass(\tooltip).text(attrs.tooltip)

app.directive \menuBox, ($document) ->
  openedMenu = null

  close = ->
    openedMenu.removeClass \menu-open if openedMenu
    openedMenu := null

  open = (element) ->
    do close
    openedMenu := element.addClass \menu-open

  $document.on(\click, close).on \keydown, (e) ->
    do close if e.which is 27 # ESC

  (scope, element, attrs) ->
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

    for child in element[0].children
      if child.tagName in <[A BUTTON]>
        child.addEventListener evt, handler

app.directive \leftBtns, (registry) ->
  restrict: \E
  templateUrl: \left-btns.html
  replace: yes
  link: (scope, element, attrs) ->
    icon = registry[scope.bar.name].icon
    element.append "<a href='#{attrs.iref}'><i class=i-#{icon}></i></a>"

app.directive \btns, ->
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
