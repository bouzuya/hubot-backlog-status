# Description
#   A Hubot script that display backlog status
#
# Dependencies:
#   "q": "1.0.1"
#
# Configuration:
#   HUBOT_BACKLOG_STATUS_USE_SLACK
#   HUBOT_BACKLOG_STATUS_SPACE_ID
#   HUBOT_BACKLOG_STATUS_API_KEY
#
# Commands:
#   hubot backlog-status <project> - display backlog status
#
# Author:
#   bouzuya <m@bouzuya.net>
#
module.exports = (robot) ->
  {Promise} = require 'q'

  isSlack = process.env.HUBOT_BACKLOG_STATUS_USE_SLACK?
  spaceId = process.env.HUBOT_BACKLOG_STATUS_SPACE_ID
  apiKey = process.env.HUBOT_BACKLOG_STATUS_API_KEY
  urlRoot = "https://#{spaceId}.backlog.jp"

  robot.respond /backlog-status\s+([_a-zA-Z0-9]+)\s*$/i, (res) ->
    projectKey = res.match[1].toUpperCase()

    res.send 'OK. Now loading...'

    get = (path, query={}) ->
      new Promise (resolve, reject) ->
        query.apiKey = apiKey
        res.http(urlRoot + path)
          .query query
          .get() (err, res, body) ->
            return reject(err) if err?
            resolve JSON.parse(body)

    getPullRequestUrl = (issue) ->
      get '/api/v2/issues/' + issue.id + '/comments'
        .then (comments) ->
          prurl = null
          comments.some (comment) ->
            pattern = /^(https?:\/\/github.com\/\S*)\s*$/m
            match = comment.content.match pattern
            prurl = match[0] if match?
            match
          issue.prurl = prurl

    eachSeries = (arr, f) ->
      arr.reduce (p, i) ->
        p.then -> f(i)
      , Promise.resolve()

    project = null
    users = null
    Promise.resolve()
    .then -> get '/api/v2/projects/' + projectKey
    .then (p) -> project = p
    .then -> get '/api/v2/projects/' + projectKey + '/users'
    .then (u) -> users = u
    .then ->
      eachSeries users, (user) ->
        get '/api/v2/issues',
          'projectId[]': project.id
          'statusId[]': [2, 3]
          'assigneeId[]': user.id
        .then (issues) ->
          user.issues = issues
        .then ->
          eachSeries user.issues, (issue) ->
            getPullRequestUrl(issue)
    .then ->
      messages = users
        .filter (user) -> user.issues.length > 0
        .map (user) ->
          user.name + ':\n' + user.issues.map((issue) ->
            [
              '  ' + urlRoot + '/view/' + issue.issueKey
              '    ' + issue.status.name + ' ' + issue.summary
              if issue.prurl then '    ' + issue.prurl else ''
            ].join('\n')
          ).join('\n')
      message = 'backlog-status result:\n' + messages.join('\n')
      res.send(if isSlack then '```\n' + message + '\n```' else message)
    , (e) ->
      robot.logger.error e
