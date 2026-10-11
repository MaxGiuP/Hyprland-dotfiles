from pathlib import Path
import os, subprocess, tempfile
BASE=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tab-alignment-') as tmp:
    root=Path(tmp)
    for name in ['NavigationRailTabArray','NavigationRailButton']:
        text=(BASE/f'modules/common/widgets/{name}.qml').read_text()
        text='\n'.join(line for line in text.splitlines() if not line.startswith('import qs'))
        (root/f'{name}.qml').write_text(text)
    (root/'qmldir').write_text('singleton Appearance 1.0 Appearance.qml\nsingleton ColorUtils 1.0 ColorUtils.qml\n')
    (root/'Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool reduceMotion:false
 property var rounding: ({full:999,small:8})
 property var colors: ({colSecondaryContainer:"#335577",colOnLayer1:"white",colPrimary:"white",colSecondaryContainerActive:"#335577",colSecondaryContainerHover:"#335577",colLayer1Active:"#112233",colLayer1Hover:"#112233"})
 property var m3colors: ({m3onSecondaryContainer:"white"})
 property var font: ({pixelSize:{normal:18}})
 property var animationCurves: ({expressiveFastSpatialDuration:80,expressiveFastSpatial:[0,0,1,1,1,1]})
 property QtObject animation: QtObject {
  property QtObject elementMove: QtObject {property int duration:80;property int type:Easing.Linear;property var bezierCurve:[0,0,1,1,1,1]}
  property QtObject elementMoveFast: QtObject {property int duration:80;property int type:Easing.Linear;property var bezierCurve:[0,0,1,1,1,1];property Component colorAnimation: Component {ColorAnimation {duration:80}}}
 }
}''')
    (root/'ColorUtils.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {function transparentize(c,a) {return "transparent"}}')
    (root/'StyledText.qml').write_text('import QtQuick\nText {font.pixelSize:Appearance.font.pixelSize.normal}')
    (root/'MaterialSymbol.qml').write_text('import QtQuick\nText {property real iconSize:24;property real fill:0;font.pixelSize:iconSize}')
    (root/'PointingHandInteraction.qml').write_text('import QtQuick\nItem {}')
    (root/'StyledToolTip.qml').write_text('import QtQuick\nQtObject {property string text;property bool extraVisibleCondition:false}')
    (root/'tst_alignment.qml').write_text('''import QtQuick
import QtQuick.Controls
import QtTest
import "."
TestCase {
 name:"RightSidebarTabAlignment";when:windowShown;width:260;height:560;visible:true
 NavigationRailTabArray {
  id:rail;x:13;y:29;width:126;height:implicitHeight
  Repeater {
   id:tabs;model:["Calendar","Hub","To Do","Timer"]
   NavigationRailButton {required property var modelData;buttonText:modelData;buttonIcon:"A";showToggledHighlight:false}
  }
 }
 function test_actualButtonGeometry() {
  const indicator=findChild(rail,"activeTabIndicator");verify(indicator!==null)
  for (let scale of [18,25]) {
   Appearance.font=({pixelSize:{normal:scale}});wait(200)
   for (let i=0;i<4;i++) {
    rail.currentIndex=i;wait(180)
    const button=tabs.itemAt(i);
    // In collapsed Material navigation, the icon occupies a 56x32 pill at top margin8.
    const origin=button.mapToItem(rail,0,button.highlightCollapsedTopMargin);
    fuzzyCompare(indicator.y,origin.y,1,"highlight must follow actual selected button y")
    fuzzyCompare(indicator.x+indicator.width/2,origin.x+button.baseSize/2,1,"highlight and icon must share a centre")
    fuzzyCompare(indicator.height,button.baseHighlightHeight,1)
   }
  }
 }
}''')
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QSG_RHI_BACKEND='software')
    result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(root),'-o','-,txt'],env=env,capture_output=True,text=True,timeout=20)
    print(result.stdout+result.stderr)
    raise SystemExit(result.returncode)
