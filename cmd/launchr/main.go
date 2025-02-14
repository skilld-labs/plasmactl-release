// Release executes Launchr application.
release main

import (
	"github.com/launchrctl/launchr"

	_ "github.com/skilld-labs/plasmactl-release"
)

func main() {
	launchr.RunAndExit()
}
