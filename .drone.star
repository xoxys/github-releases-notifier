def main(ctx):
  before = testing()

  stages = [
    linux('amd64'),
    linux('arm64'),
    linux('arm'),
  ]

  after = notification()

  for b in before:
    for s in stages:
      s['depends_on'].append(b['name'])

  for s in stages:
    for a in after:
      a['depends_on'].append(s['name'])

  return before + stages + after

def testing():
  return [{
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'testing',
    'platform': {
      'os': 'linux',
      'arch': 'amd64',
    },
    'steps': [
      {
        'name': 'vet',
        'image': 'golang:1.12',
        'commands': [
          'go vet ./...'
        ],
        'volumes': [
          {
            'name': 'gopath',
            'path': '/go'
          }
        ]
      },
      {
        'name': 'test',
        'image': 'golang:1.12',
        'commands': [
          'go test -cover ./...'
        ],
        'volumes': [
          {
            'name': 'gopath',
            'path': '/go'
          }
        ]
      }
    ],
    'volumes': [
      {
        'name': 'gopath',
        'temp': {}
      }
    ],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
        'refs/pull/**'
      ]
    }
  }]

def linux(arch):
  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'build-container-%s' % arch,
    'platform': {
      'os': 'linux',
      'arch': arch,
    },
    'steps': [
      {
        'name': 'build-push',
        'image': 'golang:1.12',
        'environment': {
          'CGO_ENABLED': '0'
        },
        'commands': [
          'go build -v -ldflags "-X main.version=${DRONE_COMMIT_SHA:0:8}" -a -tags netgo -o release/%s/github-releases-notifier' % arch
        ],
        'when': {
          'event': {
            'exclude': [
              'tag'
            ]
          }
        }
      },
      {
        'name': 'build-tag',
        'image': 'golang:1.12',
        'environment': {
          'CGO_ENABLED': '0'
        },
        'commands': [
          'go build -v -ldflags "-X main.version=${DRONE_TAG##v}" -a -tags netgo -o release/%s/github-releases-notifier' % arch
        ],
        'when': {
          'event': [
            'tag'
          ]
        }
      },
      {
        'name': 'executable',
        'image': 'golang:1.12',
        'commands': [
          './release/%s/github-releases-notifier --help' % arch
        ]
      },
      {
        'name': 'dryrun',
        'image': 'plugins/docker',
        'settings': {
          'dry_run': True,
          'tags': arch,
          'dockerfile': 'docker/Dockerfile.%s' % arch,
          'repo': 'xoxys/github-releases-notifier',
          'username': {
            'from_secret': 'docker_username'
          },
          'password': {
            'from_secret': 'docker_password'
          }
        },
        'when': {
          'event': [
            'pull_request'
          ]
        }
      },
      {
        'name': 'publish',
        'image': 'plugins/docker',
        'settings': {
          'auto_tag': True,
          'auto_tag_suffix': arch,
          'dockerfile': 'docker/Dockerfile.%s' % arch,
          'repo': 'xoxys/github-releases-notifier',
          'username': {
            'from_secret': 'docker_username'
          },
          'password': {
            'from_secret': 'docker_password'
          }
        },
        'when': {
          'event': {
            'exclude': [
              'pull_request'
            ]
          }
        }
      }
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
        'refs/pull/**'
      ]
    }
  }

def notification():
  return [{
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'notification',
    'steps': [
      {
        'name': 'manifest',
        'image': 'plugins/manifest',
        'settings': {
          'auto_tag': True,
          'username': {
            'from_secret': 'docker_username'
          },
          'password': {
            'from_secret': 'docker_password'
          },
          'spec': 'docker/manifest.tmpl',
          'ignore_missing': 'true',
        },
        'when' : {
          'status': [
            'success',
          ]
        },
      },
      {
        'name': 'readme',
        'image': 'sheogorath/readme-to-dockerhub',
        'environment': {
          'DOCKERHUB_USERNAME': {
            'from_secret': 'docker_username'
          },
          'DOCKERHUB_PASSWORD': {
            'from_secret': 'docker_password'
          },
          'DOCKERHUB_REPO_PREFIX': 'xoxys',
          'DOCKERHUB_REPO_NAME': 'github-releases-notifier',
          'README_PATH': 'README.md',
          'SHORT_DESCRIPTION': 'Receive Slack notifications for new GitHub releases'
        },
      },
      {
        'name': 'microbadger',
        'image': 'plugins/webhook',
        'settings': {
          'urls': {
            'from_secret': 'microbadger_url'
          }
        },
        'when' : {
          'status': [
            'success',
          ]
        },
      },
      {
        'name': 'matrix',
        'image': 'plugins/matrix',
        'settings': {
          'homeserver': {
            'from_secret': 'matrix_homeserver',
          },
          'password': {
            'from_secret': 'matrix_password',
          },
          'roomid': {
            'from_secret': 'matrix_roomid',
          },
          'template': 'Status: **{{ build.status }}**<br/> Build: [{{ repo.Owner }}/{{ repo.Name }}]({{ build.link }}) ({{ build.branch }}) by {{ build.author }}<br/> Message: {{ build.message }}',
          'username': {
            'from_secret': 'matrix_username',
          },
        },
      },
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**'
      ],
      'status': [
        'success',
        'failure'
      ]
    }
  }]
