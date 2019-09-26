if [ ! -f $1.mmio.yaml ]; then
  echo "specify name of MMIO description file to generate ('fletchgen' or 'alveo')"
  exit 1
fi

vhdmmio $1.mmio.yaml -P vhdl -V vhdl -H mmio-doc
