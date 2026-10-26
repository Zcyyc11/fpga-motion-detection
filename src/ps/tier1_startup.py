"""Local PYNQ startup. Run on the board; --dry-run never imports PYNQ."""
import argparse,hashlib,json,time
from pathlib import Path
from datetime import datetime,timezone

def main():
    parser=argparse.ArgumentParser(description='Load Tier1 and verify MMIO settings')
    parser.add_argument('--bit',type=Path,required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--log',type=Path)
    args=parser.parse_args()
    bit=args.bit.resolve();hwh=bit.with_suffix('.hwh')
    actual=hashlib.sha256(bit.read_bytes()).hexdigest()
    if actual.lower()!=args.sha256.lower():raise ValueError('Bitstream SHA256 mismatch')
    if not hwh.is_file():raise FileNotFoundError('Matching .hwh is required: '+str(hwh))
    settings={0x00:70,0x08:6,0x0C:320,0x10:90,0x14:1}
    result={'time_utc':datetime.now(timezone.utc).isoformat(),'bit':str(bit),
            'bit_sha256':actual,'hwh_sha256':hashlib.sha256(hwh.read_bytes()).hexdigest(),
            'mode':'dry_run' if args.dry_run else 'board','base':'0x43c00000',
            'settings':{hex(k):v for k,v in settings.items()},'startup_verified':False,'full_board_acceptance':False}
    if not args.dry_run:
        from pynq import Overlay,MMIO,Clocks
        overlay=Overlay(str(bit),download=False)
        overlay.download()
        Clocks.fclk0_mhz=125.0
        Clocks.fclk1_mhz=100.0
        result['clocks_mhz']=[float(Clocks.fclk0_mhz),float(Clocks.fclk1_mhz)]
        if abs(result['clocks_mhz'][0]-125)>0.2 or abs(result['clocks_mhz'][1]-100)>0.2:
            raise RuntimeError('Unexpected FCLK rates')
        mmio=MMIO(0x43C00000,0x10000)
        before={hex(k):int(mmio.read(k)) for k in settings}
        for offset,value in settings.items():mmio.write(offset,value)
        after={hex(k):int(mmio.read(k)) for k in settings}
        for offset,value in settings.items():
            if after[hex(offset)]!=value:raise RuntimeError('MMIO readback mismatch at '+hex(offset))
        a=int(mmio.read(0x18));time.sleep(1.0);b=int(mmio.read(0x18))
        result.update(before=before,after=after,status_before=a,status_after=b,
                      frame_advanced=((a>>16)&0x7fff)!=((b>>16)&0x7fff),
                      uart_drop_sticky=bool(b&0x80000000),startup_verified=True,
                      scope='bit download, clocks and MMIO only; HDMI/UART evidence is separate')
    text=json.dumps(result,indent=2)
    if args.log:
        with args.log.open('x',encoding='utf-8') as handle:handle.write(text+'\n')
    print(text)

if __name__=='__main__':main()
