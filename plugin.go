// Package plasmactlrelease implements a release launchr plugin
package plasmactlrelease

import (
	"context"
	"embed"
	"io/fs"

	// Ensure keyring is loaded. Required by release action
	_ "github.com/launchrctl/keyring"
	"github.com/launchrctl/launchr"
	"github.com/launchrctl/launchr/pkg/action"
)

// Embed an action directory. Tree:
// - action.yaml
// - Dockerfile
// - ...
// The content is available like action/action.yaml
//
//go:embed action
var actionfs embed.FS

func init() {
	launchr.RegisterPlugin(&Plugin{})
}

// Plugin is [launchr.Plugin] providing action.
type Plugin struct{}

// PluginInfo implements [launchr.Plugin] interface.
func (p *Plugin) PluginInfo() launchr.PluginInfo {
	return launchr.PluginInfo{}
}

// DiscoverActions implements [launchr.ActionDiscoveryPlugin] interface.
func (p *Plugin) DiscoverActions(_ context.Context) ([]*action.Action, error) {
	// Use subdirectory so the content is available in the root "./".
	subfs, err := fs.Sub(actionfs, "action")
	if err != nil {
		return nil, err
	}
	a, err := action.NewYAMLFromFS("platform:release", subfs)
	if err != nil {
		return nil, err
	}
	return []*action.Action{a}, nil
}
