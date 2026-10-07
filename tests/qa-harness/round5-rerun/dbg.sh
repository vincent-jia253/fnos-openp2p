. /path/to/projects/fnos-openp2p/src/openp2p/cmd/common
echo "SETTINGS=$SETTINGS"
openp2p_token=314159265358 openp2p_node=nas-01 apply_settings_env; echo "rc=$?"
ls -la "$DATA_DIR"
