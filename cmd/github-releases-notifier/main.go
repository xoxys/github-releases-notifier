package main

import (
	"context"
	"os"
	"strings"
	"time"

	"github.com/alexflint/go-arg"
	"github.com/go-kit/kit/log"
	"github.com/go-kit/kit/log/level"
	"github.com/joho/godotenv"
	"github.com/shurcooL/githubv4"
	"github.com/thegeeklab/github-releases-notifier/internal/handler"
	"github.com/thegeeklab/github-releases-notifier/internal/model"
	"golang.org/x/oauth2"
)

// Version of current build
var version = "unknown"

// Config of env and args
type Config struct {
	GithubToken  string        `arg:"env:GITHUB_TOKEN,required"`
	Interval     time.Duration `arg:"env:INTERVAL"`
	LogLevel     string        `arg:"env:LOG_LEVEL"`
	Repositories []string      `arg:"env:GITHUB_REPOS,-r,separate"`
	SlackHook    string        `arg:"env:SLACK_HOOK,required"`
	IgnorePre    bool          `arg:"env:IGNORE_PRE"`
}

// Token returns an oauth2 token or an error.
func (c Config) Token() *oauth2.Token {
	return &oauth2.Token{AccessToken: c.GithubToken}
}

// Version prints version string
func (Config) Version() string {
	return "github-releases-notifier " + version
}

func main() {
	_ = godotenv.Load()

	c := Config{
		Interval: time.Hour,
		LogLevel: "info",
	}
	arg.MustParse(&c)

	logger := log.NewJSONLogger(log.NewSyncWriter(os.Stdout))
	logger = log.With(logger,
		"ts", log.DefaultTimestampUTC,
		"caller", log.Caller(5),
	)

	switch strings.ToLower(c.LogLevel) {
	case "debug":
		logger = level.NewFilter(logger, level.AllowDebug())
	case "warn":
		logger = level.NewFilter(logger, level.AllowWarn())
	case "error":
		logger = level.NewFilter(logger, level.AllowError())
	default:
		logger = level.NewFilter(logger, level.AllowInfo())
	}

	tokenSource := oauth2.StaticTokenSource(c.Token())
	client := oauth2.NewClient(context.Background(), tokenSource)
	checker := &Checker{
		logger: logger,
		client: githubv4.NewClient(client),
	}

	releases := make(chan model.Repository)
	go checker.Run(c.Interval, c.Repositories, c.IgnorePre, releases)

	slack := handler.SlackSender{Hook: c.SlackHook}

	level.Info(logger).Log("msg", "waiting for new releases")
	for repository := range releases {
		if err := slack.Send(repository); err != nil {
			level.Warn(logger).Log(
				"msg", "failed to send release to messenger",
				"err", err,
			)
			continue
		}
	}
}
