# SPDX-License-Identifier: MPL-2.0
import ctypes
import json
import platform
import re
from pathlib import Path
import traceback
import uno
import unohelper
from com.sun.star.awt import XCallback, XWindowListener
from com.sun.star.ui import XDockingAreaAcceptor
from com.sun.star.task import XJob
from com.sun.star.document import XDocumentEventListener
from com.sun.star.frame import XStatusListener
from com.sun.star.view import XSelectionChangeListener
from com.sun.star.util import XModifyListener, XCloseListener

IDENTIFIER = 'org.docua.extension'
HOSTS = []
THEME_BASELINE = None

def rect(left=0, top=0, right=0, bottom=0):
    value = uno.createUnoStruct('com.sun.star.awt.Rectangle')
    value.X, value.Y, value.Width, value.Height = left, top, right, bottom
    return value

def prop(target, name, default=None):
    try:
        return target.getPropertyValue(name)
    except Exception:
        return default

def property_value(name, value):
    result = uno.createUnoStruct('com.sun.star.beans.PropertyValue')
    result.Name, result.Value = name, value
    return result

class Border(unohelper.Base, XDockingAreaAcceptor):
    def __init__(self, original, host):
        self.original, self.host, self.last = original, host, rect()
    def getContainerWindow(self):
        return self.original.getContainerWindow()
    def adjust(self, value):
        return rect(value.X, value.Y+self.host.height+(38 if 'sheet' in self.host.module else 0), value.Width+self.host.sidebar_width, value.Height+24+(26 if 'sheet' in self.host.module else 0))
    def requestDockingAreaSpace(self, value):
        return self.original.requestDockingAreaSpace(self.adjust(value))
    def setDockingAreaSpace(self, value):
        self.last = value
        self.original.setDockingAreaSpace(self.adjust(value))
    def refresh(self):
        self.setDockingAreaSpace(self.last)

class CommandStatus(unohelper.Base, XStatusListener):
    def __init__(self,host,name): self.host,self.name = host,name
    def statusChanged(self,event):
        if self.host.disposed: return
        self.host.command_states[self.name] = bool(event.IsEnabled)
        self.host.update()
    def disposing(self,event): pass

class Host(unohelper.Base, XCallback, XWindowListener, XSelectionChangeListener, XModifyListener, XCloseListener, XDocumentEventListener):
    def __init__(self, context, document, directory):
        self.context, self.document, self.directory = context, document, directory
        self.frame = document.CurrentController.Frame
        self.window = self.frame.ContainerWindow
        self.height, self.sidebar_width, self.handle = 175, 42, None
        self.disposed, self.updating, self.original, self.visible = False, False, None, []
        self.native_sidebar, self.sidebar_visible = None, False
        self.sheet_tabs = None
        self.saving = False
        self.command_states, self.status_listeners = {}, []
        self.version = ''
        try:
            provider = context.ServiceManager.createInstanceWithContext('com.sun.star.configuration.ConfigurationProvider',context)
            product = provider.createInstanceWithArguments('com.sun.star.configuration.ConfigurationAccess',(property_value('nodepath','/org.openoffice.Setup/Product'),))
            self.version = product.getPropertyValue('ooSetupVersionAboutBox')
        except Exception: pass
        self.module = next((name for name in ['com.sun.star.text.TextDocument','com.sun.star.sheet.SpreadsheetDocument','com.sun.star.presentation.PresentationDocument','com.sun.star.drawing.DrawingDocument'] if document.supportsService(name)), '')
        self.log = Path(uno.fileUrlToSystemPath(context.ServiceManager.createInstanceWithContext('com.sun.star.util.PathSubstitution',context).substituteVariables('$(user)',True))) / 'docua-adapter.log'
        self.journal = self.log.with_name('docua-backup.json')
    def notify(self, unused):
        try:
            if not self.module or self.disposed:
                return
            self.library = ctypes.CDLL(str(self.directory/'lo365-web-ribbon.dylib'))
            self.callback = ctypes.CFUNCTYPE(None,ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p)(self.command)
            self.library.ribbonCreate.argtypes = [ctypes.c_void_p,ctypes.c_void_p,type(self.callback)]
            self.library.ribbonCreate.restype = ctypes.c_void_p
            self.library.ribbonUpdate.argtypes = [ctypes.c_void_p]+[ctypes.c_double]*4+[ctypes.c_char_p,ctypes.c_bool,ctypes.c_bool,ctypes.c_bool]
            self.library.ribbonDetails.argtypes = [ctypes.c_void_p,ctypes.c_char_p]
            self.library.ribbonDestroy.argtypes = [ctypes.c_void_p]
            self.library.ribbonStartRefresh.argtypes = [ctypes.c_void_p]
            self.library.ribbonCanAttach.argtypes = [ctypes.c_void_p]
            self.library.ribbonCanAttach.restype = ctypes.c_bool
            pointer = self.window.getWindowHandle((),5)
            if not pointer or not self.library.ribbonCanAttach(pointer):
                self.log.write_text('Unsupported native view. Native interface retained.\n')
                return
            self.layout = self.frame.LayoutManager
            self.original = self.layout.getDockingAreaAcceptor()
            self.border = Border(self.original,self)
            self.layout_visible = self.layout.isVisible()
            self.layout.setVisible(False)
            try:
                self.native_sidebar = self.document.CurrentController.getSidebar()
                self.sidebar_visible = self.native_sidebar.isVisible()
                self.native_sidebar.setVisible(False)
            except Exception:
                pass
            if 'sheet' in self.module:
                settings = self.view_settings()
                self.sheet_tabs = prop(settings,'HasSheetTabs',True)
                self.set_sheet_tabs(False)
            self.layout.setDockingAreaAcceptor(self.border)
            self.border.refresh()
            self.handle = self.library.ribbonCreate(pointer,None,self.callback)
            self.window.addWindowListener(self)
            self.document.addModifyListener(self)
            self.document.addCloseListener(self)
            self.document.addDocumentEventListener(self)
            self.document.CurrentController.addSelectionChangeListener(self)
            self.watch_commands()
            self.update()
            self.library.ribbonStartRefresh(self.handle)
            self.log.write_text(json.dumps({'adapter':'public-uno','sourcePatches':False,'version':self.version,'module':self.module,'viewport':str(self.frame.ComponentWindow.getPosSize())},indent=2))
        except Exception:
            self.log.write_text(traceback.format_exc())
            self.stop(True)
    def selection(self):
        value = self.document.CurrentController.getSelection()
        if hasattr(value,'getCount') and value.getCount():
            return value.getByIndex(0)
        return value
    def update(self):
        if self.updating or self.disposed or not self.handle:
            return
        self.updating = True
        try:
            if self.layout.isVisible(): self.layout.setVisible(False)
            bounds = self.window.getPosSize()
            title = self.document.Title or 'Untitled'
            self.library.ribbonUpdate(self.handle,0,0,bounds.Width,self.height,title.encode(),self.document.isModified(),bool(self.document.URL),False)
            selection = self.selection()
            data = {'adapter':'public-uno','commandStates':self.command_states,'module':self.module,'viewX':0,'viewWidth':bounds.Width-self.sidebar_width-16,'fontName':prop(selection,'CharFontName',''),'fontSize':prop(selection,'CharHeight',12),'bold':prop(selection,'CharWeight',100)>100,'italic':str(prop(selection,'CharPosture','')).endswith('ITALIC'),'underline':bool(prop(selection,'CharUnderline',0))}
            data['libreofficeVersion'] = self.version
            try:
                undo = self.document.getUndoManager()
                data.update(canUndo=undo.isUndoPossible(),canRedo=undo.isRedoPossible())
            except Exception:
                pass
            try:
                settings = self.view_settings()
                data['zoom'] = prop(settings,'ZoomValue',100)
            except Exception:
                data['zoom'] = prop(self.document.CurrentController,'ZoomValue',100)
            family = 'CellStyles' if 'sheet' in self.module else 'ParagraphStyles' if 'text.' in self.module else 'graphics'
            data['selectedStyle'] = prop(selection,'CellStyle' if 'sheet' in self.module else 'ParaStyleName','')
            try:
                styles = self.document.StyleFamilies.getByName(family)
                names = styles.getElementNames()
                wanted = ['Standard','Title','Subtitle','Heading 1','Heading 2','Heading 3','Text Body'] if 'text.' in self.module else list(names)
                data['styles'] = [{'name':name,'label':'Normal' if name=='Standard' else name,'font':prop(styles.getByName(name),'CharFontName',''),'size':prop(styles.getByName(name),'CharHeight',12),'color':prop(styles.getByName(name),'CharColor',-1),'bold':prop(styles.getByName(name),'CharWeight',100)>100,'family':family} for name in wanted if name in names]
            except Exception:
                pass
            if 'sheet' in self.module:
                sheets = self.document.getSheets()
                data.update(sheets=[{'name':name} for name in sheets.getElementNames()],activeSheet=self.document.CurrentController.getActiveSheet().Name,sheetCount=sheets.getCount())
                try:
                    address = selection.getRangeAddress()
                    column, number = address.StartColumn, ''
                    while column >= 0:
                        number = chr(65+column%26)+number
                        column = column//26-1
                    data.update(cellAddress=number+str(address.StartRow+1),cellFormula=selection.getCellByPosition(0,0).getFormula())
                except Exception:
                    pass
            elif 'text.' in self.module:
                data['words'] = len(re.findall(r'\S+',self.document.Text.String))
                cursor = self.document.CurrentController.ViewCursor
                data['page'] = cursor.getPage()
                try:
                    page = self.document.StyleFamilies.getByName('PageStyles').getByName(cursor.PageStyleName)
                    for name in ['Width','Height','LeftMargin','RightMargin','TopMargin','BottomMargin']: data['page'+name] = prop(page,name,0)
                except Exception:
                    pass
                for name in ['ParaLeftMargin','ParaRightMargin','ParaTopMargin','ParaBottomMargin']:
                    data[name] = prop(selection,name,0)
                data['headings'] = []
                paragraphs = self.document.Text.createEnumeration()
                index = 0
                while paragraphs.hasMoreElements():
                    paragraph = paragraphs.nextElement()
                    level = prop(paragraph,'OutlineLevel',0)
                    if level:
                        data['headings'].append({'paragraph':index,'level':level,'text':paragraph.String})
                    index += 1
            else:
                pages = self.document.getDrawPages()
                current = self.document.CurrentController.getCurrentPage()
                data.update(slides=[{'index':i,'name':pages.getByIndex(i).Name,'active':pages.getByIndex(i)==current} for i in range(pages.getCount())],slideCount=pages.getCount())
            self.library.ribbonDetails(self.handle,json.dumps(data).encode())
        finally:
            self.updating = False
    def view_settings(self):
        controller = self.document.CurrentController
        return controller.getViewSettings() if hasattr(controller,'getViewSettings') else controller
    def command_url(self,command):
        url = uno.createUnoStruct('com.sun.star.util.URL')
        url.Complete = command if ':' in command else '.uno:'+command
        transformer = self.context.ServiceManager.createInstanceWithContext('com.sun.star.util.URLTransformer',self.context)
        unused, url = transformer.parseStrict(url)
        return url
    def watch_commands(self):
        self.updating = True
        try:
            for name in ['Bold','Italic','Underline','Cut','Copy','Paste','Undo','Redo','CharFontName','FontHeight','Save','InsertRows','InsertColumns','ToggleMergeCells','WrapText','InsertPage','DeletePage']:
                url = self.command_url(name)
                dispatcher = self.frame.queryDispatch(url,'',0)
                if dispatcher:
                    listener = CommandStatus(self,name)
                    self.status_listeners.append((dispatcher,listener,url))
                    dispatcher.addStatusListener(listener,url)
                else: self.command_states[name] = False
        finally:
            self.updating = False
    def set_sheet_tabs(self, visible):
        modified = self.document.isModified()
        self.view_settings().setPropertyValue('HasSheetTabs',visible)
        if not modified and self.document.isModified():
            self.document.setModified(False)
    def appearance(self):
        provider = self.context.ServiceManager.createInstanceWithContext('com.sun.star.configuration.ConfigurationProvider',self.context)
        return provider.createInstanceWithArguments('com.sun.star.configuration.ConfigurationUpdateAccess',(property_value('nodepath','/org.openoffice.Office.Common/Appearance'),))
    def dispatch(self, command, properties=()):
        command = command if ':' in command else '.uno:'+command
        url = self.command_url(command)
        if not self.frame.queryDispatch(url,'',0):
            raise ValueError('Command unavailable in this editor: '+command)
        dispatcher = self.context.ServiceManager.createInstanceWithContext('com.sun.star.frame.DispatchHelper',self.context)
        dispatcher.executeDispatch(self.frame,command,'',0,properties)
    def command(self, unused, command, argument):
        try:
            command, argument = command.decode(), argument.decode()
            if command == '@nativeTheme':
                global THEME_BASELINE
                config = self.appearance()
                if THEME_BASELINE is None:
                    stored = json.loads(self.journal.read_text()) if self.journal.exists() else {}
                    THEME_BASELINE = stored.get('originalApplicationAppearance') if stored.get('active') else config.getPropertyValue('ApplicationAppearance')
                    self.journal.write_text(json.dumps({'active':True,'originalApplicationAppearance':THEME_BASELINE},indent=2))
                value = THEME_BASELINE if argument=='restore' else int(argument)
                if config.getPropertyValue('ApplicationAppearance') != value:
                    config.setPropertyValue('ApplicationAppearance',value)
                    config.commitChanges()
                return
            if command == '@quit':
                desktop = self.context.ServiceManager.createInstanceWithContext('com.sun.star.frame.Desktop',self.context)
                desktop.terminate()
                return
            if command == '@refresh':
                self.update()
                return
            if command == '@restoreNativeUI':
                self.stop(True)
                return
            if command == '@ribbonHeight':
                self.height = max(50,min(300,int(argument)))
                self.border.refresh()
            elif command == '@focus':
                self.frame.ComponentWindow.setFocus()
            elif command == '@sidebar':
                self.sidebar_width = 320 if argument=='open' else 42
                self.border.refresh()
            elif command == '@style':
                selection = self.selection()
                if 'text.' in self.module: selection.setPropertyValue('ParaStyleName',argument)
                elif 'sheet' in self.module: selection.setPropertyValue('CellStyle',argument)
                else: selection.setPropertyValue('Style',self.document.StyleFamilies.getByName('graphics').getByName(argument))
            elif command == '@format':
                name,value = argument.split('=',1)
                target = self.selection()
                if name == 'FontHeight': name = 'CharHeight'
                if name not in ['CharFontName','CharHeight','CharColor','CharBackColor','ParaLeftMargin','ParaRightMargin','ParaTopMargin','ParaBottomMargin']:
                    raise ValueError('Unsupported formatting property')
                target.setPropertyValue(name,value if name=='CharFontName' else float(value) if name=='CharHeight' else int(value))
            elif command == '@pageSetting':
                name,value = argument.split('=',1)
                if name not in ['Width','Height','IsLandscape','LeftMargin','RightMargin','TopMargin','BottomMargin']: raise ValueError('Unsupported page property')
                selection = self.document.CurrentController.ViewCursor
                style = self.document.StyleFamilies.getByName('PageStyles').getByName(selection.PageStyleName)
                style.setPropertyValue(name,value=='true' if name=='IsLandscape' else int(value))
            elif command == '@zoom':
                try:
                    self.view_settings().setPropertyValue('ZoomValue',int(argument))
                except Exception:
                    self.document.CurrentController.setPropertyValue('ZoomValue',int(argument))
            elif command == '@cellAddress':
                self.document.CurrentController.select(self.document.CurrentController.getActiveSheet().getCellRangeByName(argument))
            elif command == '@cellFormula':
                self.selection().getCellByPosition(0,0).setFormula(argument)
            elif command == '@sheet':
                self.document.CurrentController.setActiveSheet(self.document.getSheets().getByName(argument))
            elif command == '@sheetName':
                self.document.CurrentController.getActiveSheet().Name = argument
            elif command == '@newSheet':
                sheets = self.document.getSheets()
                index = sheets.getCount()+1
                while sheets.hasByName('Sheet'+str(index)): index += 1
                name = 'Sheet'+str(index)
                sheets.insertNewByName(name,sheets.getCount())
                self.document.CurrentController.setActiveSheet(sheets.getByName(name))
            elif command == '@slide':
                self.document.CurrentController.setCurrentPage(self.document.getDrawPages().getByIndex(int(argument)))
            elif command == '@heading':
                paragraphs = self.document.Text.createEnumeration()
                for index in range(int(argument)+1): paragraph = paragraphs.nextElement()
                self.document.CurrentController.select(paragraph)
            elif command in ['@findText','@replace','@replaceAll']:
                find,_,replacement = argument.partition('\n')
                descriptor = self.document.createReplaceDescriptor()
                descriptor.SearchString,descriptor.ReplaceString = find,replacement
                if command=='@replaceAll': self.document.replaceAll(descriptor)
                else:
                    start = self.selection()
                    try:
                        found = self.document.findNext(start.getEnd() if hasattr(start,'getEnd') else start,descriptor)
                    except Exception:
                        found = None
                    if not found: found = self.document.findFirst(descriptor)
                    if found:
                        if command=='@replace': found.String = replacement
                        self.document.CurrentController.select(found)
            elif command.startswith('@'):
                self.library.ribbonDetails(self.handle,json.dumps({'notification':'This command is not yet available in the extension adapter.'}).encode())
                return
            else:
                properties = ()
                if argument and command in ['CharFontName','FontHeight']:
                    properties = (property_value(command,argument if command=='CharFontName' else float(argument)),)
                self.dispatch(command,properties)
            self.update()
        except Exception:
            self.log.write_text(traceback.format_exc())
            if self.handle:
                self.library.ribbonDetails(self.handle,json.dumps({'notification':'LibreOffice could not apply this command. Review the selected content before trying again.'}).encode())
    def stop(self, restore=False):
        if self.disposed: return
        self.disposed = True
        global THEME_BASELINE
        if THEME_BASELINE is not None and not any(host is not self and not host.disposed for host in HOSTS):
            try:
                config = self.appearance()
                config.setPropertyValue('ApplicationAppearance',THEME_BASELINE)
                config.commitChanges()
                self.journal.write_text(json.dumps({'active':False,'originalApplicationAppearance':THEME_BASELINE},indent=2))
                THEME_BASELINE = None
            except Exception:
                pass
        if self.handle:
            handle,self.handle = self.handle,None
            self.library.ribbonDestroy(handle)
        for dispatcher,listener,url in self.status_listeners:
            try: dispatcher.removeStatusListener(listener,url)
            except Exception: pass
        self.status_listeners.clear()
        if restore and self.original:
            try:
                self.layout.setDockingAreaAcceptor(self.original)
                self.original.setDockingAreaSpace(rect())
                self.layout.setVisible(self.layout_visible)
                self.layout.doLayout()
                if self.native_sidebar: self.native_sidebar.setVisible(self.sidebar_visible)
                if self.sheet_tabs is not None: self.set_sheet_tabs(self.sheet_tabs)
            except Exception:
                self.log.write_text(traceback.format_exc())
        try:
            self.window.removeWindowListener(self)
            self.document.removeModifyListener(self)
            self.document.removeCloseListener(self)
            self.document.removeDocumentEventListener(self)
            self.document.CurrentController.removeSelectionChangeListener(self)
        except Exception:
            pass
        if self in HOSTS: HOSTS.remove(self)
    def documentEventOccured(self,event):
        if self.disposed or self.sheet_tabs is None: return
        if event.EventName in ['OnSave','OnSaveAs','OnSaveTo']:
            self.saving = True
            self.set_sheet_tabs(self.sheet_tabs)
        elif event.EventName in ['OnSaveDone','OnSaveAsDone','OnSaveToDone','OnSaveFailed','OnSaveAsFailed','OnSaveToFailed']:
            self.saving = False
            self.set_sheet_tabs(False)
            self.update()
    def windowResized(self,event):
        if not self.disposed and self.original:
            self.border.refresh()
            self.update()
    def windowMoved(self,event): pass
    def windowShown(self,event): self.update()
    def windowHidden(self,event): pass
    def selectionChanged(self,event): self.update()
    def modified(self,event): self.update()
    def queryClosing(self,event,gets_ownership): self.stop(True)
    def notifyClosing(self,event): self.stop()
    def disposing(self,event): self.stop()

class StartupJob(unohelper.Base,XJob):
    def __init__(self,context): self.context = context
    def execute(self,arguments):
        if platform.system()!='Darwin' or platform.machine()!='arm64': return None
        environment = dict((item.Name,item.Value) for item in arguments).get('Environment',())
        model = dict((item.Name,item.Value) for item in environment).get('Model')
        if not model or not model.CurrentController: return None
        frame = model.CurrentController.Frame
        if any(host.frame==frame and not host.disposed for host in HOSTS): return None
        provider = self.context.getValueByName('/singletons/com.sun.star.deployment.PackageInformationProvider')
        directory = Path(uno.fileUrlToSystemPath(provider.getPackageLocation(IDENTIFIER))) / 'ui'
        host = Host(self.context,model,directory)
        HOSTS.append(host)
        self.context.ServiceManager.createInstanceWithContext('com.sun.star.awt.AsyncCallback',self.context).addCallback(host,None)
        return None

g_ImplementationHelper = unohelper.ImplementationHelper()
g_ImplementationHelper.addImplementation(StartupJob,'org.docua.StartupJob',('org.docua.StartupJob',))
