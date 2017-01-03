#! /bin/bash

if [[ $UID != 0 ]]; then
  echo "You need to run this script as root, if you feel unsafe feel free to explore."
  exit 1
fi

function install_package {
  PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $1|grep "install ok installed")
  echo Checking for $1: $PKG_OK

  if [ "" == "$PKG_OK" ]; then
    while true; do
        read -p "You need to install $1 would you like to install it now?" yn
        case $yn in
            [Yy]* ) apt-get --force-yes --yes install $1; break;;
            [Nn]* ) break;;
            * ) echo "Please answer Yy(yes) or Nn(no).";;
        esac
    done
  else
    echo "Package $1 found no need to install"
  fi
}

function write_conf_file {
cat << EOF > ./ibeacon.conf
export BLUETOOTH_DEVICE=hci0
export UUID="$UUID"
export MAJOR="$MAJOR"
export MINOR="$MINOR"
export POWER="$POWER"
EOF
}

function write_service_file {
cat << EOF > /etc/systemd/system/ibeacon.service
[Unit]
Description=iBeacon Service

[Service]
Type=idle
RemainAfterExit=yes
ExecStartPre=/bin/hciconfig $BLUETOOTH_DEVICE up
ExecStartPre=/usr/bin/hcitool -i hci0 cmd 0x08 0x0008 1e 02 01 1a 1a ff 4c 00 02 15 $UUID $MAJOR $MINOR $POWER 00
ExecStartPre=/usr/bin/hcitool -i hci0 cmd 0x08 0x0006 A0 00 A0 00 03 00 00 00 00 00 00 00 00 07 00
ExecStart=/usr/bin/hcitool -i hci0 cmd 0x08 0x000a 01
ExecStop=/bin/hciconfig $BLUETOOTH_DEVICE noleadv

[Install]
WantedBy=multi-user.target
EOF
}

function setup_ibeacon {
  if command -v python >/dev/null 2>&1; then
    read -p "Would you like to generate a new(Nn) UUID or enter your own(Oo)" yn
    case $yn in
      [Nn]* ) 
        export UUID="$((python -c 'import sys,uuid;a=uuid.uuid4().hex.upper();sys.stdout.write(" ".join([a[i:i+2] for i in range(0, len(a), 2)]))') 2>&1)"
        ;;
      [Oo]* )
        read -p "Please enter your UUID:" user_uuid
        export UUID=$user_uuid
        ;;
    esac
    read -p "What major revision number would you like to use for this beacon?" major_rev
    export MAJOR="$((python -c 'import sys;a=format(int(sys.argv[1]), "04x").upper();sys.stdout.write(" ".join([a[i:i+2] for i in range(0, len(a), 2)]))' $major_rev) 2>&1)" 
    read -p "What minor revision number would you like to use for this beacon?" minor_rev
    export MINOR="$((python -c 'import sys;a=format(int(sys.argv[1]), "04x").upper();sys.stdout.write(" ".join([a[i:i+2] for i in range(0, len(a), 2)]))' $minor_rev) 2>&1)" 
    read -p "What power value would you like to use (between -1 and -127) most Pis like -56 if you're not sure)?" power_val 
    export POWER="$((python -c 'import sys;sys.stdout.write(format(int(sys.argv[1])+256, "02x").upper())' $power_val) 2>&1)"
    read -p "Would you like to save this configuration file for future use?" yn
    case $yn in
      [Yy]* ) 
        write_conf_file
        ;;
      [Nn]* ) 
          echo "As you are not choosing to write this to a file, you may need these later: "
          echo BLUETOOTH_DEVICE=hci0
          echo UUID="$UUID"
          echo MAJOR="$MAJOR"
          echo MINOR="$MINOR"
          echo POWER="$POWER"
        ;;
    esac
  else
    echo "Unfortunately you need Python installed if you are going to generate your own configuration file."
  fi
}

if [ ! -f ./ibeacon.conf ]; then
  setup_ibeacon
else
  while true; do
      read -p "It appears you already have a configuration file, do you want to modify it?" yn
      case $yn in
          [Yy]* ) setup_ibeacon; break;;
          [Nn]* ) . ./ibeacon.conf; break;;
          * ) echo "Please answer Yy(yes) or Nn(no).";;
      esac
  done
fi

install_package bluez

write_service_file

systemctl daemon-reload
systemctl enable ibeacon.service
systemctl start ibeacon.service
