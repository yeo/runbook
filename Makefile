owner := optyhq
commit := $(shell git rev-parse HEAD)
name  := $(owner)/runbook
repo  := $(name)-$(commit)

docker:
	docker build -t $(repo) .

push:
	docker tag $(repo) $(name)
	#docker push name

