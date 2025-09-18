# MintMac-Project
[**Current Inventory**](https://docs.google.com/spreadsheets/d/1raWZw5cAPOhREMKeLRIhVgSCsU74mNR-6P-lN2q04wY/edit?usp=sharing)\
Re-imaging IMACS for Mint Linux use


## Tools Used:

  **Gparted** - https://gparted.org/ \
  **CloneZilla** - https://clonezilla.org/


## Commands:
+ _Mounting_
   - Create directory to mount the  \
    sudo mkdir /media/"usbname"

          sudo mkdir /media/usb

     
+ _Find USB (find the one that has the scripts)_ 
  - lsblk -l 

        sdba
          sdba1
          sdba2
            
+ _Mount USB_ \
  sudo mount /dev/"sdba1" /media/"usbname" 
      
      sudo mount /dev/sdba1 /media/usb


+ _Rename -_ \
sudo ./rename --old mintmain --new mint"newnumber" --index "newnumber" --gecos "mint"newnumber"

      sudo ./rename --old mintmain --new mint10 --index 10 --gecos "mint10"



## USB's:
_D85 - **Tools**\
_F82 - **ISO**

