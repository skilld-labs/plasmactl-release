// Package plasmactlrelease implements a release launchr plugin
package plasmactlrelease

import (
	"context"
	"embed"
	"io/fs"
)

// Embed an action directory. Tree:
// - action.yaml
// - Dockerfile
// - ...
// The content is available like action/action.yaml
//
//go:embed action
var actionfs embed.FS

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
	a, err := action.NewYAMLFromFS("my_embed_action", subfs)
	if err != nil {
		return nil, err
	}
	return []*action.Action{a}, nil
}
