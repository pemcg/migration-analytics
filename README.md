# migration-analytics


## Installation

Clone source git repository

```
git clone https://github.com/pemcg/migration-analytics.git && cd migration-analytics
```

Install required gems

```
gem install rest-client # or bundle install if using Bundler
# ensure ruby and rubygems is installed if gem command failed
```

## Usage

### Short version

```
./get_token.rb | awk '{print $3}' | xargs ./ma_collector.rb -t
```

Expecting locally running ManageIQ and default credentials.

### Long version

1. get token to ManageIQ API

```
./get_token.rb -s MIQ_HOSTNAME_OR_IP
# Should return: Authentication token: ca6ead....ad4, use -h for help
```

2. Run data collection

```
./ma_collector.rb -s MIQ_HOSTNAME_OR_IP -t TOKEN
# Should return:
#   Analyzing vCenter
#   Analyzing VMs
# Use -h for help
```

3. Get collected data

Default collected data path is ```/tmp/migration_analytics```

```
/tmp/migration_analytics/
├── vcs
│   └── VMware.json
└── vms
    ├── avm-rhel7-mini.json
    ├── big-ip-ve-east.json
    ├── big-ip-ve-emea.json
...
    └── last-vm-8apr-002.json

```