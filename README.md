# MintMac-Project
Re-imaging IMACS for Mint Linux use

Tools Used:
Gparted - https://gparted.org/
CloneZilla - https://clonezilla.org/

Current Inventory:
https://docs.google.com/spreadsheets/d/1raWZw5cAPOhREMKeLRIhVgSCsU74mNR-6P-lN2q04wY/edit?usp=sharing

Commands:

Mounting -


  Create dir
  
  sudo mkdir /media/"usbname"
        Ex. 
      
    sudo mkdir /media/usb
        
  
  Find USB (find the one that has the scripts)
  
  lsblk -l 
      Ex. 
        
    sdba
      sdba1
      sdba2
            
  
  Mount USB
  
  sudo mount /dev/"sdba1" /media/"usbname"
      Ex. 
        
    sudo mount /dev/sdba1 /media/usb


Rename - sudo ./rename --old mintmain --new mint"newnumber" --index "newnumber" --gecos "mint"newnumber"

  Ex. 
    
    sudo ./rename --old mintmain --new mint10 --index 10 --gecos "mint10"



USB's:

_D85 - Tools

_F82 - ISO

